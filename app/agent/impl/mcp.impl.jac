impl McpClient.start(server_cmd: list[str], timeout_s: float = -1.0) -> dict[str, any] {
    return mcp_start(self, server_cmd, timeout_s);
}

impl McpClient.list_tools(timeout_s: float = -1.0) -> dict[str, any] {
    return mcp_list_tools(self, timeout_s);
}

impl McpClient.call_tool(
    name: str, arguments: dict[str, any], timeout_s: float = -1.0
) -> dict[str, any] {
    return mcp_call_tool(self, name, arguments, timeout_s);
}

impl McpClient.stop -> dict[str, any] {
    return mcp_stop(self);
}

impl create_mcp_client(timeout_s: float = DEFAULT_TIMEOUT_S) -> McpClient {
    return McpClient(timeout_s=timeout_s);
}

impl _alive(client: McpClient) -> bool {
    if client.transport == "http" {
        return client.initialized and not client.dead;
    }
    if client.proc is None {
        return False;
    }
    return client.proc.poll() is None;
}

impl _ensure_io(client: McpClient) {
    if client.write_lock is None {
        client.write_lock = threading.Lock();
    }
    if client.reader_stop is None {
        client.reader_stop = threading.Event();
    }
}

impl _reader_loop(client: McpClient) {
    stop = client.reader_stop;
    proc = client.proc;
    if proc is None or proc.stdout is None {
        return;
    }
    while stop is None or not stop.is_set() {
        try {
            line_raw: any = proc.stdout.readline();
        } except Exception {
            break;
        }
        if not line_raw {
            break;
        }
        line_s: str = str(line_raw).strip();
        if not line_s {
            continue;
        }
        try {
            parsed: any = json.loads(line_s);
        } except Exception {
            continue;
        }
        if not isinstance(parsed, dict) {
            continue;
        }
        rid: any = parsed.get("id");
        method: any = parsed.get("method");
        if rid is not None and method is not None {
            handler: any = client.on_request;
            if handler is not None {
                raw_params: any = parsed.get("params");
                p_in: dict[str, any] = raw_params if isinstance(raw_params, dict) else {};
                t = threading.Thread(
                    target=_serve_inbound,
                    args=(client, rid, str(method), p_in),
                    daemon=True,
                    name="mcp-inbound",
                );
                t.start();
            } else {
                reply: dict[str, any] = {
                    "jsonrpc": "2.0",
                    "id": rid,
                    "error": {
                        "code": -32601,
                        "message": "method not supported by client: " + str(method),
                    },
                };
                try {
                    _write_line(client, reply);
                } except Exception {}
            }
            continue;
        }
        if rid is not None and method is None {
            key = str(rid);
            waiter: any = client.pending.get(key);
            if waiter is not None {
                waiter["msg"] = parsed;
                ev: any = waiter.get("event");
                if ev is not None {
                    ev.set();
                }
            }
            continue;
        }
        if len(client.notifications) < MAX_NOTIFICATIONS {
            client.notifications.append(parsed);
        }
    }
    if stop is None or not stop.is_set() {
        client.dead = True;
    }
    for leftover in list(client.pending.values()) {
        if isinstance(leftover, dict) and leftover.get("msg") is None {
            leftover["eof"] = True;
            ev2: any = leftover.get("event");
            if ev2 is not None {
                ev2.set();
            }
        }
    }
}

impl _http_error_response(client: McpClient, he: any) -> dict[str, any] {
    raw: bytes = b"";
    try {
        raw = he.read();
    } except Exception {}
    parsed: any = None;
    try {
        parsed = json.loads(raw.decode("utf-8", "replace"));
    } except Exception {}
    if isinstance(parsed, dict) and ("error" in parsed or "result" in parsed) {
        return parsed;
    }
    if he.code == 404 or he.code >= 500 {
        client.dead = True;
    }
    raise RuntimeError(f"http {he.code} from mcp server");
}

impl _http_exchange(
    client: McpClient, msg: dict[str, any], timeout_s: float, expect_body: bool
) -> any {
    hdrs: dict[str, str] = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    };
    for (hk, hv) in client.headers.items() {
        hdrs[str(hk)] = str(hv);
    }
    if client.session_id {
        hdrs["Mcp-Session-Id"] = client.session_id;
    }
    body: bytes = json.dumps(msg).encode("utf-8");
    req = urllib.request.Request(client.url, data=body, headers=hdrs, method="POST");
    resp: any = None;
    try {
        resp = urllib.request.urlopen(req, timeout=timeout_s);
    } except urllib.error.HTTPError as he {
        return _http_error_response(client, he);
    } except urllib.error.URLError as ue {
        rsn: any = getattr(ue, "reason", ue);
        if isinstance(rsn, TimeoutError) or "timed out" in str(rsn).lower() {
            raise TimeoutError(f"http request timed out after {timeout_s}s");
        }
        client.dead = True;
        raise RuntimeError(f"http transport failed: {ue}");
    }
    try {
        sid: any = resp.headers.get("Mcp-Session-Id", "");
        if sid and not client.session_id {
            client.session_id = str(sid);
        }
        status: int = int(resp.status);
        if status == 202 or not expect_body {
            return None;
        }
        ctype: str = str(resp.headers.get("Content-Type", "") or "");
        if ctype.startswith("text/event-stream") {
            while True {
                line_raw: any = resp.readline();
                if not line_raw {
                    break;
                }
                if isinstance(line_raw, bytes) {
                    line_s: str = line_raw.decode("utf-8", "replace").strip();
                } else {
                    line_s: str = str(line_raw).strip();
                }
                if not line_s.startswith("data:") {
                    continue;
                }
                payload: str = line_s[len("data:"):].strip();
                if not payload {
                    continue;
                }
                try {
                    got: any = json.loads(payload);
                } except Exception {
                    continue;
                }
                if isinstance(got, dict)
                    and got.get("id") == msg.get("id")
                    and "method" not in got
                {
                    return got;
                }
                if isinstance(got, dict) and len(client.notifications) < MAX_NOTIFICATIONS {
                    client.notifications.append(got);
                }
            }
            return {
                "jsonrpc": "2.0",
                "id": msg.get("id"),
                "error": {"code": -32000, "message": "sse stream ended without a response"},
            };
        }
        raw2: bytes = resp.read();
        parsed2: any = json.loads(raw2.decode("utf-8", "replace"));
        if isinstance(parsed2, dict) {
            return parsed2;
        }
        raise RuntimeError("mcp server returned a non-object response");
    } finally {
        try {
            resp.close();
        } except Exception {}
    }
}

impl _start_reader(client: McpClient) {
    _ensure_io(client);
    if client.reader_thread is not None and client.reader_thread.is_alive() {
        return;
    }
    client.reader_stop.clear();
    t = threading.Thread(target=_reader_loop, args=(client,), daemon=True, name="mcp-reader");
    client.reader_thread = t;
    t.start();
}

impl _stop_reader(client: McpClient) {
    if client.reader_stop is not None {
        client.reader_stop.set();
    }
    client.reader_thread = None;
}

impl _write_line(client: McpClient, msg: dict[str, any]) {
    if client.transport == "http" {
        _http_exchange(client, msg, client.timeout_s, False);
        return;
    }
    if not _alive(client) or client.proc.stdin is None {
        raise RuntimeError("mcp server not running");
    }
    line = json.dumps(msg) + "\n";
    lock: any = client.write_lock;
    if lock is not None {
        lock.acquire();
        try {
            client.proc.stdin.write(line);
            client.proc.stdin.flush();
        } finally {
            lock.release();
        }
    } else {
        client.proc.stdin.write(line);
        client.proc.stdin.flush();
    }
}

impl _request(
    client: McpClient, method: str, params: dict[str, any], timeout_s: float
) -> dict[str, any] {
    if client.transport == "http" {
        rid_h: int = client.next_id;
        client.next_id += 1;
        req_h: dict[str, any] = {
            "jsonrpc": "2.0",
            "id": rid_h,
            "method": method,
            "params": params or {},
        };
        got_h: any = None;
        try {
            got_h = _http_exchange(client, req_h, timeout_s, True);
        } except TimeoutError {
            raise TimeoutError(f"timed out waiting for {method}");
        }
        if got_h is None {
            return {
                "jsonrpc": "2.0",
                "id": rid_h,
                "error": {"code": -32000, "message": "http server accepted without a response"},
            };
        }
        return got_h as dict[str, any];
    }
    _ensure_io(client);
    rid = client.next_id;
    client.next_id += 1;
    key = str(rid);
    client.pending[key] = {"event": threading.Event(), "msg": None};
    req: dict[str, any] = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}};
    try {
        _write_line(client, req);
    } except Exception as e {
        client.pending.pop(key, None);
        raise RuntimeError(f"mcp write failed: {e}");
    }
    deadline = time.monotonic() + timeout_s;
    while True {
        remaining = max(0.01, deadline - time.monotonic());
        waiter: any = client.pending.get(key);
        if waiter is None {
            raise RuntimeError("mcp response waiter vanished");
        }
        if waiter.get("msg") is not None {
            client.pending.pop(key, None);
            got: any = waiter["msg"];
            return got as dict[str, any];
        }
        if waiter.get("eof") {
            client.pending.pop(key, None);
            raise RuntimeError("mcp server closed connection");
        }
        ok = waiter["event"].wait(timeout=remaining);
        if not ok and time.monotonic() >= deadline {
            client.pending.pop(key, None);
            raise TimeoutError(f"timed out waiting for {method}");
        }
    }
}

impl _response_payload(resp: dict[str, any]) -> dict[str, any] {
    err: any = resp.get("error");
    if isinstance(err, dict) and err is not None {
        code = err.get("code", "");
        message = str(err.get("message", "unknown mcp error"));
        return {"ok": False, "error": f"{message} (code {code})"};
    }
    result: any = resp.get("result");
    if not isinstance(result, dict) {
        return {"ok": True, "result": {}};
    }
    return {"ok": True, "result": result};
}

impl _effective_timeout(client: McpClient, timeout_s: float) -> float {
    if timeout_s > 0.0 {
        return timeout_s;
    }
    return client.timeout_s;
}

impl mcp_start(
    client: McpClient,
    server_cmd: list[str],
    timeout_s: float = -1.0,
    env_extra: dict[str, str] | None = None,
    cwd: str = "",
) -> dict[str, any] {
    if not server_cmd {
        return {"ok": False, "error": "server_cmd must not be empty"};
    }
    if _alive(client) {
        return {"ok": False, "error": "mcp client already started"};
    }
    client.dead = False;
    timeout = _effective_timeout(client, timeout_s);
    _ensure_io(client);
    popen_env: any = None;
    if env_extra {
        base_env: dict[str, str] = dict(os.environ);
        for (env_k, env_v) in env_extra.items() {
            base_env[str(env_k)] = str(env_v);
        }
        popen_env = base_env;
    }
    popen_cwd: any = None;
    if cwd {
        popen_cwd = str(cwd);
    }
    try {
        client.proc = subprocess.Popen(
            [str(c) for c in server_cmd],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            env=popen_env,
            cwd=popen_cwd,
        );
    } except Exception as e {
        client.proc = None;
        return {"ok": False, "error": f"failed to spawn mcp server: {e}"};
    }
    client.server_cmd = [str(c) for c in server_cmd];
    _start_reader(client);
    init_params: dict[str, any] = {
        "protocolVersion": MCP_PROTOCOL_VERSION,
        "capabilities": {"sampling": {}, "elicitation": {}},
        "clientInfo": {"name": "jackal", "version": "0.1.0"},
    };
    try {
        resp = _request(client, "initialize", init_params, timeout);
    } except Exception as e {
        mcp_stop(client);
        return {"ok": False, "error": f"initialize failed: {e}"};
    }
    payload = _response_payload(resp);
    if not payload["ok"] {
        mcp_stop(client);
        return payload;
    }
    result: any = payload["result"];
    pv = str(result.get("protocolVersion", ""));
    if pv {
        client.protocol_version = pv;
    }
    raw_info: any = result.get("serverInfo");
    info: dict[str, any] = {};
    if isinstance(raw_info, dict) {
        info = raw_info;
    }
    client.server_info = info;
    try {
        _write_line(client, {"jsonrpc": "2.0", "method": "notifications/initialized"});
    } except Exception as e {
        mcp_stop(client);
        return {"ok": False, "error": f"initialized notification failed: {e}"};
    }
    client.initialized = True;
    out: dict[str, any] = {"ok": True};
    if info.get("name") {
        out["server_name"] = str(info.get("name"));
    }
    if pv {
        out["protocol_version"] = pv;
    }
    return out;
}

impl mcp_start_http(
    client: McpClient, url: str, headers: dict[str, str] | None = None, timeout_s: float = -1.0
) -> dict[str, any] {
    if not url or not str(url).startswith(("http://", "https://")) {
        return {"ok": False, "error": "http mcp server needs an http(s) url"};
    }
    if _alive(client) {
        return {"ok": False, "error": "mcp client already started"};
    }
    client.transport = "http";
    client.dead = False;
    client.proc = None;
    client.url = str(url);
    client.session_id = "";
    client.headers = {};
    if isinstance(headers, dict) {
        for (hk, hv) in headers.items() {
            client.headers[str(hk)] = str(hv);
        }
    }
    timeout = _effective_timeout(client, timeout_s);
    _ensure_io(client);
    init_params: dict[str, any] = {
        "protocolVersion": MCP_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "jackal", "version": "0.1.0"},
    };
    try {
        resp = _request(client, "initialize", init_params, timeout);
    } except Exception as e {
        return {"ok": False, "error": f"initialize failed: {e}"};
    }
    payload = _response_payload(resp);
    if not payload["ok"] {
        return payload;
    }
    result: any = payload["result"];
    pv = str(result.get("protocolVersion", ""));
    if pv {
        client.protocol_version = pv;
    }
    raw_info: any = result.get("serverInfo");
    info: dict[str, any] = {};
    if isinstance(raw_info, dict) {
        info = raw_info;
    }
    client.server_info = info;
    try {
        _write_line(client, {"jsonrpc": "2.0", "method": "notifications/initialized"});
    } except Exception as e {
        return {"ok": False, "error": f"initialized notification failed: {e}"};
    }
    client.initialized = True;
    out: dict[str, any] = {"ok": True};
    if info.get("name") {
        out["server_name"] = str(info.get("name"));
    }
    if pv {
        out["protocol_version"] = pv;
    }
    return out;
}

impl mcp_list_tools(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    timeout = _effective_timeout(client, timeout_s);
    tools: list[dict[str, any]] = [];
    cursor: str = "";
    pages: int = 0;
    while True {
        params: dict[str, any] = {};
        if cursor {
            params["cursor"] = cursor;
        }
        try {
            resp = _request(client, "tools/list", params, timeout);
        } except Exception as e {
            return {"ok": False, "error": str(e)};
        }
        payload = _response_payload(resp);
        if not payload["ok"] {
            return payload;
        }
        result: any = payload["result"];
        raw_tools: any = result.get("tools", []);
        if isinstance(raw_tools, list) {
            for t in raw_tools {
                if isinstance(t, dict) and t.get("name") {
                    schema: any = t.get("inputSchema");
                    tools.append({
                        "name": str(t.get("name")),
                        "description": str(t.get("description", "")),
                        "inputSchema": schema if isinstance(schema, dict) else {},
                    });
                }
            }
        }
        pages += 1;
        nc: any = result.get("nextCursor");
        next_cur: str = str(nc) if nc else "";
        if not next_cur or pages >= MAX_LIST_PAGES {
            break;
        }
        cursor = next_cur;
    }
    return {"ok": True, "tools": tools};
}

impl mcp_call_tool(
    client: McpClient, name: str, arguments: dict[str, any], timeout_s: float = -1.0
) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    if not name {
        return {"ok": False, "error": "tool name must not be empty"};
    }
    args: dict[str, any] = {};
    if isinstance(arguments, dict) {
        args = arguments;
    }
    timeout = _effective_timeout(client, timeout_s);
    params: dict[str, any] = {"name": str(name), "arguments": args};
    try {
        resp = _request(client, "tools/call", params, timeout);
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
    payload = _response_payload(resp);
    if not payload["ok"] {
        return payload;
    }
    result: any = payload["result"];
    parts: list[str] = [];
    raw_content: any = result.get("content", []);
    blocks: list[dict[str, any]] = [];
    if isinstance(raw_content, list) {
        for block in raw_content {
            if not isinstance(block, dict) {
                continue;
            }
            blocks.append(block);
            btype: str = str(block.get("type", ""));
            if btype == "text" {
                parts.append(str(block.get("text", "")));
            } elif btype == "image" {
                parts.append(
                    "[image: "
                        + str(block.get("mimeType", "unknown"))
                        + ", "
                        + str(len(str(block.get("data", ""))))
                        + " b64 chars]",
                );
            } elif btype == "audio" {
                parts.append(
                    "[audio: "
                        + str(block.get("mimeType", "unknown"))
                        + ", "
                        + str(len(str(block.get("data", ""))))
                        + " b64 chars]",
                );
            } elif btype == "resource" {
                res: any = block.get("resource");
                if isinstance(res, dict) {
                    stub: str = "[resource: " + str(res.get("uri", "unknown"));
                    if res.get("mimeType") {
                        stub += " " + str(res.get("mimeType"));
                    }
                    stub += "]";
                    parts.append(stub);
                    if res.get("text") {
                        parts.append(str(res.get("text", "")));
                    }
                } else {
                    parts.append("[resource: unknown]");
                }
            } elif btype == "resource_link" {
                parts.append(
                    "[resource_link: " + str(block.get("uri", block.get("name", "unknown"))) + "]"
                );
            } else {
                parts.append("[unsupported content block: " + (btype or "unknown") + "]");
            }
        }
    }
    text = "\n".join(parts);
    is_err = bool(result.get("isError", False));
    out: dict[str, any] = {"ok": True, "result": text, "is_error": is_err};
    if blocks {
        out["content"] = blocks;
    }
    structured: any = result.get("structuredContent");
    if isinstance(structured, dict) {
        out["structured"] = structured;
    }
    return out;
}

impl mcp_stop(client: McpClient) -> dict[str, any] {
    if client.transport == "http" {
        if client.session_id {
            try {
                hdrs: dict[str, str] = dict(client.headers);
                hdrs["Mcp-Session-Id"] = client.session_id;
                req = urllib.request.Request(client.url, data=b"", headers=hdrs, method="DELETE");
                resp: any = urllib.request.urlopen(req, timeout=2.0);
                try {
                    resp.close();
                } except Exception {}
            } except Exception {}
        }
        client.initialized = False;
        client.session_id = "";
        client.pending = {};
        return {"ok": True};
    }
    proc = client.proc;
    if proc is not None {
        try {
            if proc.poll() is None {
                if proc.stdin is not None {
                    try {
                        proc.stdin.close();
                    } except Exception {}
                }
                proc.terminate();
                try {
                    proc.wait(timeout=2.0);
                } except Exception {
                    try {
                        proc.kill();
                        proc.wait(timeout=2.0);
                    } except Exception {}
                }
            }
        } except Exception {}
    }
    _stop_reader(client);
    client.proc = None;
    client.initialized = False;
    client.pending = {};
    return {"ok": True};
}

impl mcp_tool_specs(
    client: McpClient, prefix: str = "", timeout_s: float = -1.0
) -> list[dict[str, any]] {
    res = mcp_list_tools(client, timeout_s);
    specs: list[dict[str, any]] = [];
    if not res["ok"] {
        return specs;
    }
    tools: any = res.get("tools", []);
    for t in tools {
        if not isinstance(t, dict) {
            continue;
        }
        name = str(t.get("name", ""));
        if not name {
            continue;
        }
        raw_schema: any = t.get("inputSchema");
        params: dict[str, any] = {};
        if isinstance(raw_schema, dict) and raw_schema {
            params = raw_schema;
        } else {
            params = {"type": "object", "properties": {}, "required": []};
        }
        full_name = prefix + name;
        specs.append({
            "name": full_name,
            "description": str(t.get("description", "")),
            "parameters": params,
        });
    }
    return specs;
}

impl mcp_is_alive(client: McpClient) -> bool {
    return _alive(client) and not client.dead;
}

impl mcp_drain_notifications(client: McpClient) -> list[dict[str, any]] {
    out: list[dict[str, any]] = list(client.notifications);
    client.notifications.clear();
    return out;
}

impl mcp_list_prompts(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    timeout = _effective_timeout(client, timeout_s);
    prompts: list[dict[str, any]] = [];
    cursor: str = "";
    pages: int = 0;
    while True {
        params: dict[str, any] = {};
        if cursor {
            params["cursor"] = cursor;
        }
        try {
            resp = _request(client, "prompts/list", params, timeout);
        } except Exception as e {
            return {"ok": False, "error": str(e)};
        }
        payload = _response_payload(resp);
        if not payload["ok"] {
            return payload;
        }
        result: any = payload["result"];
        raw_prompts: any = result.get("prompts", []);
        if isinstance(raw_prompts, list) {
            for pr in raw_prompts {
                if isinstance(pr, dict) and pr.get("name") {
                    args_out: list[any] = [];
                    raw_args: any = pr.get("arguments", []);
                    if isinstance(raw_args, list) {
                        args_out = raw_args;
                    }
                    prompts.append({
                        "name": str(pr.get("name")),
                        "description": str(pr.get("description", "")),
                        "arguments": args_out,
                    });
                }
            }
        }
        pages += 1;
        nc: any = result.get("nextCursor");
        next_cur: str = str(nc) if nc else "";
        if not next_cur or pages >= MAX_LIST_PAGES {
            break;
        }
        cursor = next_cur;
    }
    return {"ok": True, "prompts": prompts};
}

impl mcp_get_prompt(
    client: McpClient, name: str, arguments: dict[str, any], timeout_s: float = -1.0
) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    if not name {
        return {"ok": False, "error": "prompt name must not be empty"};
    }
    args: dict[str, any] = {};
    if isinstance(arguments, dict) {
        args = arguments;
    }
    params: dict[str, any] = {"name": str(name), "arguments": args};
    timeout = _effective_timeout(client, timeout_s);
    try {
        resp = _request(client, "prompts/get", params, timeout);
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
    payload = _response_payload(resp);
    if not payload["ok"] {
        return payload;
    }
    result: any = payload["result"];
    messages: list[dict[str, any]] = [];
    raw_msgs: any = result.get("messages", []);
    if isinstance(raw_msgs, list) {
        for m in raw_msgs {
            if isinstance(m, dict) {
                messages.append(m);
            }
        }
    }
    return {"ok": True, "description": str(result.get("description", "")), "messages": messages};
}

impl mcp_list_resources(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    timeout = _effective_timeout(client, timeout_s);
    resources: list[dict[str, any]] = [];
    cursor: str = "";
    pages: int = 0;
    while True {
        params: dict[str, any] = {};
        if cursor {
            params["cursor"] = cursor;
        }
        try {
            resp = _request(client, "resources/list", params, timeout);
        } except Exception as e {
            return {"ok": False, "error": str(e)};
        }
        payload = _response_payload(resp);
        if not payload["ok"] {
            return payload;
        }
        result: any = payload["result"];
        raw_res: any = result.get("resources", []);
        if isinstance(raw_res, list) {
            for r in raw_res {
                if isinstance(r, dict) and r.get("uri") {
                    resources.append({
                        "uri": str(r.get("uri")),
                        "name": str(r.get("name", "")),
                        "description": str(r.get("description", "")),
                        "mimeType": str(r.get("mimeType", "")),
                    });
                }
            }
        }
        pages += 1;
        nc: any = result.get("nextCursor");
        next_cur: str = str(nc) if nc else "";
        if not next_cur or pages >= MAX_LIST_PAGES {
            break;
        }
        cursor = next_cur;
    }
    return {"ok": True, "resources": resources};
}

impl mcp_read_resource(client: McpClient, uri: str, timeout_s: float = -1.0) -> dict[str, any] {
    if not client.initialized or not _alive(client) {
        return {"ok": False, "error": "mcp client not initialized"};
    }
    if not uri {
        return {"ok": False, "error": "resource uri must not be empty"};
    }
    params: dict[str, any] = {"uri": str(uri)};
    timeout = _effective_timeout(client, timeout_s);
    try {
        resp = _request(client, "resources/read", params, timeout);
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
    payload = _response_payload(resp);
    if not payload["ok"] {
        return payload;
    }
    result: any = payload["result"];
    parts: list[str] = [];
    contents: list[dict[str, any]] = [];
    raw_contents: any = result.get("contents", []);
    if isinstance(raw_contents, list) {
        for c in raw_contents {
            if not isinstance(c, dict) {
                continue;
            }
            contents.append(c);
            if c.get("text") is not None {
                parts.append(str(c.get("text", "")));
            } elif isinstance(c.get("blob"), str) {
                blob: str = str(c.get("blob", ""));
                mt: str = str(c.get("mimeType", "unknown"));
                parts.append("[blob resource: " + mt + ", " + str(len(blob)) + " b64 chars]");
            } else {
                parts.append("[resource without text or blob content]");
            }
        }
    }
    return {"ok": True, "uri": str(uri), "text": "\n".join(parts), "contents": contents};
}

impl _serve_inbound(client: McpClient, rid: any, method: str, params: dict[str, any]) {
    reply: dict[str, any] = {
        "jsonrpc": "2.0",
        "id": rid,
        "error": {"code": -32603, "message": "client handler failed"},
    };
    try {
        handler: any = client.on_request;
        verdict: any = None;
        if handler is not None {
            verdict = handler(method, params);
        }
        code_i: int = -32000;
        if isinstance(verdict, dict) and verdict.get("code") is not None {
            try {
                code_i = int(verdict.get("code"));
            } except Exception {
                code_i = -32000;
            }
        }
        if isinstance(verdict, dict) and verdict.get("ok") is True {
            res: any = verdict.get("result");
            reply = {"jsonrpc": "2.0", "id": rid, "result": res if isinstance(res, dict) else {}};
        } elif isinstance(verdict, dict) {
            reply = {
                "jsonrpc": "2.0",
                "id": rid,
                "error": {"code": code_i, "message": str(verdict.get("message", "request failed"))},
            };
        } else {
            reply["error"] = {
                "code": -32603,
                "message": "client handler returned an invalid verdict",
            };
        }
    } except Exception as e {
        reply["error"] = {"code": -32603, "message": "client handler failed: " + str(e)};
    }
    try {
        _write_line(client, reply);
    } except Exception {}
}

impl mcp_set_request_handler(client: McpClient, handler: any) {
    client.on_request = handler;
}
