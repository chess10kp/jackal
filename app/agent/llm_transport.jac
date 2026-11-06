"""Jackal model layer - owned ReAct loop, injectable transport. No byllm.

The transport is a swappable component (Cordis fiber candidate: provides
"llm.transport"). The loop is plain code we control end to end, so the
event stream here becomes the harness's UI protocol verbatim.

Transport contract: `stream(messages, tool_defs)` yields normalized chunk
dicts as they arrive:
    {"content": str}                          - one text token/fragment
    {"tool_calls": [ ...openai tool_call... ]} - complete calls, emitted once
    {"error": str}                            - transport-level failure
"""

import os;
import json;
import time;
import from .llm_http_stream { HttpStreamResponse, post_json_stream }
import from .tool_spec { ToolSpec, MAX_TOOL_RESULT }
import from .provider_routes {
    PROVIDER_ROUTES,
    provider_for,
    credential_error,
}
import from .registry {
    ToolRegistry,
    as_tool_specs,
    invoke,
}
import from .plugin_bridge {
    PluginBridge,
    context_gate,
    prepare_provider_request,
    resolve_ext_model,
    tool_call_gate,
    tool_result_gate,
}
import from .plugin_bridge_hooks { notify_after_provider_response }




"""Cooperative turn-abort flag. Session owns one per active turn; the UI
thread flips `cancelled` and the ReAct loop checks it between stream chunks
and before each tool call. Plain fields — safe to set from another thread."""
obj:pub Transport {
    has base_url: str = "https://api.openai.com/v1",
        api_key: str = "",
        model: str = "",
        thinking: str = "";

    # Pi `after_provider_response` parity (see docs/AFTER-PROVIDER-RESPONSE-NOTE.md):
    # informational-only {status, headers}, fired when response headers arrive,
    # before the body is consumed. hook_bridge is the PluginBridge whose Node
    # sidecar hosts extension hooks; None disables. hook_timeout bounds the
    # stdio round trip so a hung handler never stalls stream-open.
    has hook_bridge: any = None,
        hook_timeout: float = 2.0;

    def _build_body(messages: list[dict[str, any]], tool_defs: list[dict[str, any]]) -> dict[str, any] {
        # Single source of truth for the request body so tests can assert its
        # exact shape without network I/O. With thinking == "" the returned
        # dict is byte-identical to the pre-thinking-level body (no extra keys).
        # dict[str, any]: "reasoning" carries a nested dict while other
        # values are scalars, so the bare inference collapses to literals.
        body: dict[str, any] = {
            "model": self.model,
            "messages": messages,
            "stream": True,
        };
        if tool_defs { body["tools"] = tool_defs; }
        # Reasoning effort: these bodies are OpenAI/OpenRouter chat-completion
        # style, and OpenRouter's documented form is top-level
        # `reasoning: {"effort": ...}` (OpenAI-compatible too via mapping).
        # Omitted entirely when no level was requested.
        if self.thinking {
            reasoning: dict[str, any] = {"effort": self.thinking};
            body["reasoning"] = reasoning;
        }
        return body;
    }

    def stream(
        messages: list[dict[str, any]],
        tool_defs: list[dict[str, any]],
        on_chunk: Callable[[dict[str, any], any], bool],
        stream_context: any,
    ) {
        body = self._build_body(messages, tool_defs);
        headers: dict[str, str] = {};
        if self.api_key { headers["Authorization"] = "Bearer " + self.api_key; }
        url = self.base_url.rstrip("/") + "/chat/completions";
        self._open_stream(url, headers, body, on_chunk, stream_context);
    }

    """Fire the informational after_provider_response hook (Pi parity).
    Never raises and never blocks longer than hook_timeout — a failing or
    hung hook must not affect the stream."""
    def _notify_response(status: int, headers: dict[str, str]) {
        if self.hook_bridge is None {
            return;
        }
        try {
            notify_after_provider_response(
                self.hook_bridge,
                status,
                json.dumps(headers),
                self.hook_timeout,
            );
        } except Exception {
            # Informational: hook failures are silent by design.
        }
    }

    """POST `body` to `url` and yield normalized chunks (shared by native
    and P10 provider transports)."""
    def _open_stream(
        url: str,
        headers: dict[str, str],
        body: dict[str, any],
        on_chunk: Callable[[dict[str, any], any], bool],
        stream_context: any,
    ) {
        calls: dict[int, dict[str, any]] = {};
        request_headers: dict[str, str] = dict(headers);
        request_headers["Content-Type"] = "application/json";
        request_headers["Accept"] = "text/event-stream";
        r: HttpStreamResponse | None = None;
        try {
            r = post_json_stream(url, request_headers, body);
            # Fire strictly before the first line is read so handlers observe
            # "provider answered" ahead of any content event downstream.
            self._notify_response(r.status, r.headers);
            if r.status != 200 {
                detail = r.read().decode("utf-8", "replace")[:400];
                error_chunk: dict[str, any] = {"error": f"HTTP {r.status}: {detail}"};
                on_chunk(error_chunk, stream_context);
                return;
            }
            while True {
                raw_line: str = r.readline();
                if not raw_line {
                    break;
                }
                line_end: int = raw_line.find("\r");
                if line_end < 0 { line_end = raw_line.find("\n"); }
                line: str = raw_line if line_end < 0 else raw_line[:line_end];
                if line.find("data: ") != 0 { continue; }
                payload: str = line[6:];
                if payload == "[DONE]" { break; }
                chunk: dict[str, any] = json.loads(payload) as dict[str, any];
                choices: list[dict[str, any]] = chunk["choices"] as list[dict[str, any]];
                choice: dict[str, any] = choices[0];
                delta: dict[str, any] = choice.get("delta", {}) as dict[str, any];
                piece: any = delta.get("content");
                if piece {
                    content_chunk: dict[str, any] = {"content": str(piece)};
                    if not on_chunk(content_chunk, stream_context) { return; }
                }
                tool_calls: list[dict[str, any]] = delta.get("tool_calls", []) as list[dict[str, any]];
                for raw_tc in tool_calls {
                    tc: dict[str, any] = raw_tc;
                    idx = int(tc.get("index", 0));
                    acc = calls.get(idx);
                    if acc is None {
                        fn_acc: dict[str, any] = {"name": "", "arguments": ""};
                        acc_new: dict[str, any] = {
                            "id": tc.get("id", ""),
                            "type": "function",
                            "function": fn_acc,
                        };
                        acc = acc_new;
                        calls[idx] = acc;
                    }
                    fn: dict[str, any] = tc.get("function", {}) as dict[str, any];
                    acc_fn: dict[str, any] = acc["function"] as dict[str, any];
                    if fn.get("id") { acc["id"] = fn["id"]; }
                    if fn.get("name") {
                        acc_fn["name"] = str(acc_fn["name"]) + str(fn["name"]);
                    }
                    if fn.get("arguments") {
                        acc_fn["arguments"] = str(acc_fn["arguments"]) + str(fn["arguments"]);
                    }
                }
            }
        } finally {
            if r is not None { r.close(); }
        }
        if calls {
            ordered: list[dict[str, any]] = [];
            for i in sorted(calls) { ordered.append(calls[i]); }
            tool_calls_chunk: dict[str, any] = {"tool_calls": ordered};
            on_chunk(tool_calls_chunk, stream_context);
        }
    }
}


"""Scripted, offline transport behind the `mock` route (models `mock`,
`mockllm`, `mock/*`) — the backbone of the e2e test harness.

JACKAL_MOCK_SCRIPT names a JSON file holding a list of responses; each model
call consumes the next one (cursor per script path, per process):
  {"text": "..."}                                   plain answer
  {"text": "...", "tool_calls": [{"name": "read_file", "args": {...}}]}
  {"error": "HTTP 500: boom"}                       stream error event
Without a script (or once it is exhausted) the reply echoes the last user
message as "mock: <text>". JACKAL_MOCK_LOG, when set, receives one JSON line
per call ({"call", "messages", "last", "tools"}) so tests can assert exactly
what the model was sent."""
glob _mock_cursor: dict[str, int] = {};

def _mock_last_user(messages: list[dict[str, any]]) -> str {
    for i in range(len(messages) - 1, -1, -1) {
        m: dict[str, any] = messages[i];
        if str(m.get("role", "")) == "user" {
            return str(m.get("content", ""));
        }
    }
    return "";
}

def _mock_next_response(script_path: str) -> dict[str, any] | None {
    if not script_path or not os.path.exists(script_path) {
        return None;
    }
    try {
        fh = open(script_path, "r", encoding="utf-8");
        steps: any = json.loads(fh.read());
        fh.close();
    } except Exception as e {
        error_response: dict[str, any] = {"error": "mock script unreadable: " + str(e)};
        return error_response;
    }
    if not isinstance(steps, list) {
        error_response: dict[str, any] = {"error": "mock script must be a JSON list"};
        return error_response;
    }
    idx: int = _mock_cursor.get(script_path, 0);
    _mock_cursor[script_path] = idx + 1;
    if idx >= len(steps) or not isinstance(steps[idx], dict) {
        return None;
    }
    return steps[idx];
}

obj MockTransport (Transport) {
    override def stream(
        messages: list[dict[str, any]],
        tool_defs: list[dict[str, any]],
        on_chunk: Callable[[dict[str, any], any], bool],
        stream_context: any,
    ) {
        script_path: str = os.environ.get("JACKAL_MOCK_SCRIPT", "");
        step: dict[str, any] | None = _mock_next_response(script_path);
        log_path: str = os.environ.get("JACKAL_MOCK_LOG", "");
        if log_path {
            tool_names: list[str] = [];
            for d in tool_defs {
                fn: dict[str, any] = d.get("function", {}) as dict[str, any] if isinstance(d, dict) else {};
                tool_names.append(str(fn.get("name", "")) if isinstance(fn, dict) else "");
            }
            last: dict[str, any] = messages[-1] if messages else {};
            last_fields: dict[str, any] = {
                "role": str(last.get("role", "")),
                "content": str(last.get("content", "")),
            };
            log_entry: dict[str, any] = {
                "call": _mock_cursor.get(script_path, 0),
                "messages": len(messages),
                "last": last_fields,
                "tools": tool_names,
            };
            try {
                lf = open(log_path, "a", encoding="utf-8");
                lf.write(json.dumps(log_entry) + "\n");
                lf.close();
            } except Exception {
            }
        }
        if step is None {
            fallback_response: dict[str, any] = {"text": "mock: " + _mock_last_user(messages)};
            step = fallback_response;
        }
        if "error" in step {
            error_chunk: dict[str, any] = {"error": str(step["error"])};
                on_chunk(error_chunk, stream_context);
            return;
        }
        text: str = str(step.get("text", "") or "");
        # Real providers emit many small deltas; short answers stay one
        # chunk (tests assert exact chunk lists), long ones split into
        # ~80-char pieces so frontends exercise per-chunk drain paths.
        if len(text) <= 160 {
            if text {
                content_chunk: dict[str, any] = {"content": text};
                if not on_chunk(content_chunk, stream_context) { return; }
            }
        } else {
            i: int = 0;
            while i < len(text) {
                content_chunk: dict[str, any] = {"content": text[i:i + 80]};
                if not on_chunk(content_chunk, stream_context) { return; }
                i += 80;
            }
        }
        raw_calls: any = step.get("tool_calls", []);
        if isinstance(raw_calls, list) and raw_calls {
            calls: list[dict[str, any]] = [];
            n: int = 0;
            for rc in raw_calls {
                if not isinstance(rc, dict) { continue; }
                n += 1;
                function_call: dict[str, any] = {
                    "name": str(rc.get("name", "")),
                    "arguments": json.dumps(rc.get("args", {})),
                };
                mock_call: dict[str, any] = {
                    "id": "mock_call_" + str(n),
                    "type": "function",
                    "function": function_call,
                };
                calls.append(mock_call);
            }
            tool_calls_chunk: dict[str, any] = {"tool_calls": calls};
            on_chunk(tool_calls_chunk, stream_context);
        }
    }
}


"""The id the MODEL picker must advertise for `name` under `provider`.

Routing dispatches on the provider prefix, so bare catalog names like
"deepseek-chat" misroute to openai_compat (wrong endpoint and credential
check). Ids that already route to their advertising provider (mock,
openrouter's nested vendor/model ids) pass through untouched."""
def routed_model_id(provider: str, name: str) -> str {
    if provider_for(name) == provider {
        return name;
    }
    return provider + "/" + name;
}


"""Pick a transport from the model name. Provider table lives here so the
whole model edge is one swappable module.

`model` is always explicit (callers may override the session default global
per turn); `thinking` optionally carries a reasoning level
("off"|"minimal"|"low"|"medium"|"high", "" = omit from request body).

Historical wiring preserved verbatim: unresolved `ext/` ids still fall back
to the OpenAI-compatible endpoint (session resolves ext ids through
make_ext_transport FIRST; this is the native fallback path). `mock` ids get
the table's local:// marker instead of silently billing a real endpoint.
"""
def make_transport(model: str = "", thinking: str = "", hook_bridge: any = None) -> Transport {
    provider = provider_for(model);
    if provider == "ext" { provider = "openai_compat"; }
    route: dict[str, any] = PROVIDER_ROUTES[provider];
    prefix = provider + "/";
    stripped = model;
    if model.startswith(prefix) { stripped = model[len(prefix):]; }
    key_env = str(route.get("key_env", ""));
    api_key = os.environ.get(key_env, "") if key_env else "";
    base_url_env = str(route.get("base_url_env", ""));
    base_url = os.environ.get(base_url_env, str(route["base_url"])) if base_url_env else str(route["base_url"]);
    if provider == "mock" {
        return MockTransport(base_url=base_url, model=stripped, thinking=thinking);
    }
    return Transport(
        base_url=base_url,
        api_key=api_key,
        model=stripped,
        thinking=thinking,
        hook_bridge=hook_bridge,
    );
}


"""P10 provider transport: serves `ext/<extension>/<model>` model ids.

Resolves the owning extension's provider via bridge state, fires Pi's
`before_provider_request` hook before each POST (body/url/headers mutation —
full request control, trusted in-process code), then streams identically to
the native transport."""
obj ProviderTransport (Transport) {
    has ext_bridge: any = None,
        ext_cfg: dict[str, any] = {};

    override def stream(
        messages: list[dict[str, any]],
        tool_defs: list[dict[str, any]],
        on_chunk: Callable[[dict[str, any], any], bool],
        stream_context: any,
    ) {
        body = self._build_body(messages, tool_defs);
        headers: dict[str, str] = {};
        if self.api_key { headers["Authorization"] = "Bearer " + self.api_key; }
        # Typed intermediate: the literal-arg rstrip chain infers LiteralString,
        # which the hook rewrite below cannot assign back into.
        url: str = self.base_url.rstrip("/") + "/chat/completions";
        if self.ext_bridge is not None {
            try {
                prepped = prepare_provider_request(
                    self.ext_bridge as PluginBridge,
                    self.model,
                    url,
                    headers,
                    body,
                );
                url = str(prepped.get("url", url));
                h2: any = prepped.get("headers");
                if isinstance(h2, dict) {
                    raw_headers: dict[str, any] = h2 as dict[str, any];
                    for (key, value) in raw_headers.items() {
                        headers[str(key)] = str(value);
                    }
                }
                b2: any = prepped.get("body");
                if isinstance(b2, dict) { body = b2; }
            } except Exception {
                # Hook failure never blocks the request.
            }
        }
        self._open_stream(url, headers, body, on_chunk, stream_context);
    }
}


"""Build a transport for an extension-declared model id.

Returns None when the id is not in the ext/ namespace or no extension
declared it — callers fall back to native routing."""
def make_ext_transport(bridge: any, model_id: str, thinking: str = "") -> ProviderTransport | None {
    if bridge is None {
        return None;
    }
    cfg = resolve_ext_model(bridge as PluginBridge, model_id);
    if cfg is None {
        return None;
    }
    t = ProviderTransport(
        base_url=str(cfg.get("base_url") or "https://api.openai.com/v1"),
        model=str(cfg.get("model", "")),
        thinking=thinking,
    );
    t.ext_bridge = bridge;
    t.ext_cfg = cfg;
    # Same informational hook surface as native transports (ProviderTransport
    # additionally fires before_provider_request in its own stream override).
    t.hook_bridge = bridge;
    return t;
}
