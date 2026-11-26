impl Transport._build_body(
    messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
) -> dict[str, any] {
    body: dict[str, any] = {"model": self.model, "messages": messages, "stream": True};
    if tool_defs {
        body["tools"] = tool_defs;
    }
    if self.thinking {
        body["reasoning"] = {"effort": self.thinking};
    }
    return body;
}

impl Transport.stream(
    messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
) -> Iterator[dict[str, any]] {
    body = self._build_body(messages, tool_defs);
    headers: dict[str, str] = {};
    if self.api_key {
        headers["Authorization"] = "Bearer " + self.api_key;
    }
    url = self.base_url.rstrip("/") + "/chat/completions";
    yield from self._open_stream(url, headers, body);
}

impl Transport._notify_response(status: int, headers: dict[str, str]) {
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
    } except Exception {}
}

impl Transport._open_stream(
    url: str, headers: dict[str, str], body: dict[str, any]
) -> Iterator[dict[str, any]] {
    calls: dict[int, dict[str, any]] = {};
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    );
    r: any = None;
    try {
        try {
            r = urllib.request.urlopen(req, timeout=300.0);
        } except urllib.error.HTTPError as e {
            hdrs: dict[str, str] = {};
            for (hk, hv) in e.headers.items() {
                hdrs[str(hk)] = str(hv);
            }
            self._notify_response(int(e.code), hdrs);
            detail = e.read().decode("utf-8", "replace")[:400];
            yield {"error": f"HTTP {e.code}: {detail}"};
            return;
        }
        rhdrs: dict[str, str] = {};
        for (hk, hv) in r.headers.items() {
            rhdrs[str(hk)] = str(hv);
        }
        self._notify_response(int(r.status), rhdrs);
        while True {
            raw: bytes = r.readline();
            if not raw {
                break;
            }
            line: str = raw.decode("utf-8", "replace").rstrip("\r\n");
            if not line.startswith("data: ") {
                continue;
            }
            payload: str = line[len("data: "):];
            if payload == "[DONE]" {
                break;
            }
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
                if fn.get("id") {
                    acc["id"] = fn["id"];
                }
                if fn.get("name") {
                    acc["function"]["name"] = str(acc["function"]["name"]) + str(fn["name"]);
                }
                if fn.get("arguments") {
                    acc["function"]["arguments"] = str(acc["function"]["arguments"])
                        + str(fn["arguments"]);
                }
            }
        }
    } finally {
        if r is not None {
            r.close();
        }
    }
    if calls {
        ordered: list[dict[str, any]] = [];
        for i in sorted(calls) {
            ordered.append(calls[i]);
        }
        yield {"tool_calls": ordered};
    }
}

impl _mock_last_user(messages: list[dict[str, any]]) -> str {
    for i in range(len(messages) - 1, -1, -1) {
        m: dict[str, any] = messages[i];
        if str(m.get("role", "")) == "user" {
            return str(m.get("content", ""));
        }
    }
    return "";
}

impl _mock_next_response(script_path: str) -> dict[str, any] | None {
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

impl MockTransport.stream(
    messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
) -> Iterator[dict[str, any]] {
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
        } except Exception {}
    }
    if step is None {
        step = {"text": "mock: " + _mock_last_user(messages)};
    }
    if "error" in step {
        yield {"error": str(step["error"])};
        return;
    }
    text: str = str(step.get("text", "") or "");
    if len(text) <= 160 {
        if text {
            yield {"content": text};
        }
    } else {
        i: int = 0;
        while i < len(text) {
            yield {"content": text[i:i + 80]};
            i += 80;
        }
    }
    raw_calls: any = step.get("tool_calls", []);
    if isinstance(raw_calls, list) and raw_calls {
        calls: list[dict[str, any]] = [];
        n: int = 0;
        for rc in raw_calls {
            if not isinstance(rc, dict) {
                continue;
            }
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

impl provider_for(model: str) -> str {
    if model.startswith("openrouter/") {
        return "openrouter";
    }
    if model.startswith("deepseek/") {
        return "deepseek";
    }
    if model.startswith("zai/") {
        return "zai";
    }
    if model == "mock" or model == "mockllm" or model.startswith("mock/") {
        return "mock";
    }
    if model.startswith("ext/") {
        return "ext";
    }
    return "openai_compat";
}

impl routed_model_id(provider: str, name: str) -> str {
    if provider_for(name) == provider {
        return name;
    }
    return provider + "/" + name;
}

impl credential_error(model: str) -> str {
    try {
        provider = provider_for(model);
        if provider == "ext" {
            return "";
        }
        route: any = PROVIDER_ROUTES.get(provider);
        if route is None {
            return "";
        }
        key_env = str(route.get("key_env", ""));
        if not key_env {
            return "";
        }
        if os.environ.get(key_env, "") {
            return "";
        }
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

impl make_transport(model: str = "", thinking: str = "", hook_bridge: any = None) -> Transport {
    provider = provider_for(model);
    if provider == "ext" {
        provider = "openai_compat";
    }
    route: dict[str, any] = PROVIDER_ROUTES[provider];
    prefix = provider + "/";
    stripped = model;
    if model.startswith(prefix) {
        stripped = model[len(prefix):];
    }
    key_env = str(route.get("key_env", ""));
    api_key = os.environ.get(key_env, "") if key_env else "";
    base_url_env = str(route.get("base_url_env", ""));
    base_url = os.environ.get(base_url_env, str(route["base_url"]))
        if base_url_env
        else str(route["base_url"]);
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

impl ProviderTransport.stream(
    messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
) -> Iterator[dict[str, any]] {
    body = self._build_body(messages, tool_defs);
    headers: dict[str, str] = {};
    if self.api_key {
        headers["Authorization"] = "Bearer " + self.api_key;
    }
    url: str = self.base_url.rstrip("/") + "/chat/completions";
    if self.ext_bridge is not None {
        try {
            prepped = prepare_provider_request(
                self.ext_bridge as PluginBridge, self.model, url, headers, body
            );
            url = str(prepped.get("url", url));
            h2: any = prepped.get("headers");
            if isinstance(h2, dict) {
                headers = h2;
            }
            b2: any = prepped.get("body");
            if isinstance(b2, dict) {
                body = b2;
            }
        } except Exception {}
    }
    yield from self._open_stream(url, headers, body);
}

impl make_ext_transport(
    bridge: PluginBridge | None, model_id: str, thinking: str = ""
) -> ProviderTransport | None {
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
    t.hook_bridge = bridge;
    return t;
}
