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
import from collections.abc { Generator }
import from .tool_spec { ToolSpec, MAX_TOOL_RESULT }
import from .registry {
    ToolRegistry,
    as_tool_specs,
    invoke,
}
import from .plugin_bridge {
    PluginBridge,
    context_gate,
    fire_hook,
    prepare_provider_request,
    resolve_ext_model,
    tool_call_gate,
    tool_result_gate,
}




"""Cooperative turn-abort flag. Session owns one per active turn; the UI
thread flips `cancelled` and the ReAct loop checks it between stream chunks
and before each tool call. Plain fields — safe to set from another thread."""
obj Transport {
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
        if self.thinking { body["reasoning"] = {"effort": self.thinking}; }
        return body;
    }

    def stream(messages: list[dict[str, any]], tool_defs: list[dict[str, any]]) -> Generator[dict[str, any], None, None] {
        import httpx;
        body = self._build_body(messages, tool_defs);
        headers: dict[str, str] = {};
        if self.api_key { headers["Authorization"] = "Bearer " + self.api_key; }
        url = self.base_url.rstrip("/") + "/chat/completions";
        yield from self._open_stream(url, headers, body);
    }

    """Fire the informational after_provider_response hook (Pi parity).
    Never raises and never blocks longer than hook_timeout — a failing or
    hung hook must not affect the stream."""
    def _notify_response(status: int, headers: dict[str, str]) {
        if self.hook_bridge is None {
            return;
        }
        try {
            fire_hook(
                self.hook_bridge as PluginBridge,
                "after_provider_response",
                {"status": status, "headers": dict(headers)},
                timeout=self.hook_timeout,
            );
        } except Exception {
            # Informational: hook failures are silent by design.
        }
    }

    """POST `body` to `url` and yield normalized chunks (shared by native
    and P10 provider transports)."""
    def _open_stream(url: str, headers: dict[str, str], body: dict[str, any]) -> Generator[dict[str, any], None, None] {
        import httpx;
        calls: dict[int, dict[str, any]] = {};
        client_obj: any = httpx.Client(timeout=300.0);
        r: any = None;
        try {
            ctx: any = client_obj.stream("POST", url, json=body, headers=headers);
            r = ctx.__enter__();
            # Fire strictly before the first line is read so handlers observe
            # "provider answered" ahead of any content event downstream.
            self._notify_response(r.status_code, dict(r.headers));
            if r.status_code != 200 {
                detail = r.read().decode("utf-8", "replace")[:400];
                yield {"error": f"HTTP {r.status_code}: {detail}"};
                return;
            }
                for raw_line in r.iter_lines() {
                    line: any = raw_line;
                    if not line.startswith("data: ") { continue; }
                    payload: any = line[len("data: "):];
                    if payload == "[DONE]" { break; }
                    chunk: any = json.loads(payload);
                    delta: any = chunk["choices"][0].get("delta", {});
                    piece: any = delta.get("content");
                    if piece {
                        yield {"content": str(piece)};
                    }
                    for raw_tc in delta.get("tool_calls", []) {
                        tc: any = raw_tc;
                        idx = int(tc.get("index", 0));
                        acc = calls.get(idx);
                        if acc is None {
                            acc = {
                                "id": tc.get("id", ""),
                                "type": "function",
                                "function": {"name": "", "arguments": ""},
                            };
                            calls[idx] = acc;
                        }
                        fn: any = tc.get("function", {});
                        if fn.get("id") { acc["id"] = fn["id"]; }
                        if fn.get("name") {
                            acc["function"]["name"] = str(acc["function"]["name"]) + str(fn["name"]);
                        }
                        if fn.get("arguments") {
                            acc["function"]["arguments"] = str(acc["function"]["arguments"]) + str(fn["arguments"]);
                        }
                    }
                }
        } finally {
            if r is not None { r.close(); }
            client_obj.close();
        }
        if calls {
            ordered: list[dict[str, any]] = [];
            for i in sorted(calls) { ordered.append(calls[i]); }
            yield {"tool_calls": ordered};
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
        fh: any = open(script_path, "r", encoding="utf-8");
        steps: any = json.loads(fh.read());
        fh.close();
    } except Exception as e {
        return {"error": "mock script unreadable: " + str(e)};
    }
    if not isinstance(steps, list) {
        return {"error": "mock script must be a JSON list"};
    }
    idx: int = _mock_cursor.get(script_path, 0);
    _mock_cursor[script_path] = idx + 1;
    if idx >= len(steps) or not isinstance(steps[idx], dict) {
        return None;
    }
    return steps[idx];
}

obj MockTransport (Transport) {
    override def stream(messages: list[dict[str, any]], tool_defs: list[dict[str, any]]) -> Generator[dict[str, any], None, None] {
        script_path: str = os.environ.get("JACKAL_MOCK_SCRIPT", "");
        step: dict[str, any] | None = _mock_next_response(script_path);
        log_path: str = os.environ.get("JACKAL_MOCK_LOG", "");
        if log_path {
            tool_names: list[str] = [];
            for d in tool_defs {
                fn: any = d.get("function", {}) if isinstance(d, dict) else {};
                tool_names.append(str(fn.get("name", "")) if isinstance(fn, dict) else "");
            }
            last: dict[str, any] = messages[-1] if messages else {};
            log_entry: dict[str, any] = {
                "call": _mock_cursor.get(script_path, 0),
                "messages": len(messages),
                "last": {"role": str(last.get("role", "")), "content": str(last.get("content", ""))},
                "tools": tool_names,
            };
            try {
                lf: any = open(log_path, "a", encoding="utf-8");
                lf.write(json.dumps(log_entry) + "\n");
                lf.close();
            } except Exception {
            }
        }
        if step is None {
            step = {"text": "mock: " + _mock_last_user(messages)};
        }
        if "error" in step {
            yield {"error": str(step["error"])};
            return;
        }
        text: str = str(step.get("text", "") or "");
        # Two pieces so frontends exercise incremental streaming.
        half: int = len(text) // 2;
        if text[:half] { yield {"content": text[:half]}; }
        if text[half:] { yield {"content": text[half:]}; }
        raw_calls: any = step.get("tool_calls", []);
        if isinstance(raw_calls, list) and raw_calls {
            calls: list[dict[str, any]] = [];
            n: int = 0;
            for rc in raw_calls {
                if not isinstance(rc, dict) { continue; }
                n += 1;
                calls.append({
                    "id": "mock_call_" + str(n),
                    "type": "function",
                    "function": {
                        "name": str(rc.get("name", "")),
                        "arguments": json.dumps(rc.get("args", {})),
                    },
                });
            }
            yield {"tool_calls": calls};
        }
    }
}


"""fx-style provider-first routing (see ~/notes/fx-model-routing.md).

One table owns every provider fact — endpoint, credential env var, catalog —
and both routing (`provider_for`) and credential validation
(`credential_error`) dispatch through it. Prefix matching is CASE-SENSITIVE
on purpose: it preserves the exact `startswith` semantics make_transport had
before the table existed ("OpenRouter/..." was never a routed id).

Route fields:
  description   human-facing provider blurb (/model UI)
  base_url      default chat-completions endpoint
  base_url_env  optional env var overriding base_url (openai_compat only)
  key_env       bearer-token env var; "" = provider needs no credential
  models        static catalog hints (informational)
"""
glob PROVIDER_ROUTES: dict[str, dict[str, any]] = {
    "openrouter": {
        "description": "OpenRouter multi-provider gateway",
        "base_url": "https://openrouter.ai/api/v1",
        "base_url_env": "",
        "key_env": "OPENROUTER_API_KEY",
        "models": ["anthropic/claude-sonnet-5", "openai/gpt-5"],
    },
    "deepseek": {
        "description": "DeepSeek API",
        "base_url": "https://api.deepseek.com/v1",
        "base_url_env": "",
        "key_env": "DEEPSEEK_API_KEY",
        "models": ["deepseek-chat", "deepseek-reasoner"],
    },
    "zai": {
        "description": "Z.ai GLM models (OpenAI-compatible)",
        "base_url": "https://api.z.ai/api/paas/v4",
        "base_url_env": "",
        "key_env": "ZAI_API_KEY",
        # Fallback hints; GET /models is not officially documented but
        # works (auth-gated), so a live catalog replaces these when a
        # ZAI_API_KEY is present.
        "models": ["glm-4.6", "glm-4.5", "glm-4.5-air"],
    },
    "openai_compat": {
        "description": "Any OpenAI-compatible chat-completions endpoint",
        "base_url": "https://api.openai.com/v1",
        "base_url_env": "OPENAI_COMPAT_BASE",
        "key_env": "OPENAI_API_KEY",
        "models": ["gpt-4o", "gpt-4o-mini"],
    },
    "mock": {
        "description": "Local mockllm (no network, no credential)",
        "base_url": "local://mockllm",
        "base_url_env": "",
        "key_env": "",
        "models": ["mock"],
    },
};


"""Map a model id to its provider id (pure function — reads nothing).

Dispatch:
  "openrouter/<model>"          -> "openrouter"
  "deepseek/<model>"            -> "deepseek"
  "zai/<model>"                 -> "zai"
  "mock" | "mockllm" | "mock/*" -> "mock"
  "ext/<extension>/<model>"     -> "ext" (resolved via plugin bridge)
  anything else                 -> "openai_compat"
"""
def provider_for(model: str) -> str {
    if model.startswith("openrouter/") { return "openrouter"; }
    if model.startswith("deepseek/") { return "deepseek"; }
    if model.startswith("zai/") { return "zai"; }
    if model == "mock" or model == "mockllm" or model.startswith("mock/") {
        return "mock";
    }
    if model.startswith("ext/") { return "ext"; }
    return "openai_compat";
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


"""fx-style actionable credential check. Returns "" when the model is
usable; otherwise ONE sentence naming the exact fix. Reads only os.environ
and never raises.
"""
def credential_error(model: str) -> str {
    try {
        provider = provider_for(model);
        if provider == "ext" { return ""; }
        route: any = PROVIDER_ROUTES.get(provider);
        if route is None { return ""; }
        key_env = str(route.get("key_env", ""));
        if not key_env { return ""; }
        if os.environ.get(key_env, "") { return ""; }
        fix = f'set {key_env}';
        if provider == "openai_compat" {
            fix += " (or point OPENAI_COMPAT_BASE at your endpoint)";
        }
        return (
            f'model "{model}" routes via {provider} — {fix}'
            + " or pick another provider (/model for options)."
        );
    } except Exception {
        return "";
    }
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

    override def stream(messages: list[dict[str, any]], tool_defs: list[dict[str, any]]) -> Generator[dict[str, any], None, None] {
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
                if isinstance(h2, dict) { headers = h2; }
                b2: any = prepped.get("body");
                if isinstance(b2, dict) { body = b2; }
            } except Exception {
                # Hook failure never blocks the request.
            }
        }
        yield from self._open_stream(url, headers, body);
    }
}


"""Build a transport for an extension-declared model id.

Returns None when the id is not in the ext/ namespace or no extension
declared it — callers fall back to native routing."""
def make_ext_transport(bridge: PluginBridge | None, model_id: str, thinking: str = "") -> ProviderTransport | None {
    cfg = resolve_ext_model(bridge, model_id);
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
