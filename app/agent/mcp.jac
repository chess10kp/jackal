"""MCP client — talks to `jac mcp` (or any MCP server) as a stdio subprocess.

Transport: newline-delimited JSON-RPC 2.0 over stdin/stdout (verified against
`jac mcp`, which speaks one JSON object per line, no Content-Length framing).
Lifecycle: start -> initialize handshake -> notifications/initialized ->
tools/list / tools/call -> stop.

Style mirrors plugin_bridge.jac: obj state + module-level functions taking
the client as first arg, defensive dict access, background stdout reader
thread with per-id correlation events. The public seam NEVER raises — every
entry point returns {"ok": True, ...} or {"ok": False, "error": ...}.
"""

import json;
import os;
# NOTE: shutil/tempfile are unused by runtime code but REQUIRED here: the
# same-stem test annex (mcp.test.jac) resolves names against the base
# module's namespace at merge time. Do not remove.
import shutil;
import subprocess;
import sys;
import tempfile;
import threading;
import time;

glob DEFAULT_TIMEOUT_S: float = 15.0,
     MAX_NOTIFICATIONS: int = 1000,
     MAX_LIST_PAGES: int = 64;

# Protocol version we offer during initialize; servers negotiate down.
glob MCP_PROTOCOL_VERSION: str = "2025-06-18";


obj McpClient {
    """State holder for one MCP server subprocess."""
    has dead: bool = False,
        proc: any = None,
        server_cmd: list[str] = [],
        next_id: int = 1,
        timeout_s: float = DEFAULT_TIMEOUT_S,
        initialized: bool = False,
        protocol_version: str = "",
        server_info: dict[str, any] = {},
        pending: dict[str, any] = {},
        notifications: list[dict[str, any]] = [],
        write_lock: any = None,
        reader_stop: any = None,
        reader_thread: any = None;

    def start(server_cmd: list[str], timeout_s: float = -1.0) -> dict[str, any] {
        return mcp_start(self, server_cmd, timeout_s);
    }

    def list_tools(timeout_s: float = -1.0) -> dict[str, any] {
        return mcp_list_tools(self, timeout_s);
    }

    def call_tool(name: str, arguments: dict[str, any], timeout_s: float = -1.0) -> dict[str, any] {
        return mcp_call_tool(self, name, arguments, timeout_s);
    }

    def stop() -> dict[str, any] {
        return mcp_stop(self);
    }
}


def create_mcp_client(timeout_s: float = DEFAULT_TIMEOUT_S) -> McpClient {
    return McpClient(timeout_s=timeout_s);
}


def _alive(client: McpClient) -> bool {
    if client.proc is None {
        return False;
    }
    return client.proc.poll() is None;
}


def _ensure_io(client: McpClient) {
    if client.write_lock is None {
        client.write_lock = threading.Lock();
    }
    if client.reader_stop is None {
        client.reader_stop = threading.Event();
    }
}


"""Background stdout reader — routes responses by id, buffers notifications."""
def _reader_loop(client: McpClient) {
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
            continue;  # skip non-JSON noise on the transport
        }
        if not isinstance(parsed, dict) {
            continue;
        }
        rid: any = parsed.get("id");
        method: any = parsed.get("method");
        if rid is not None and method is not None {
            # Server->client REQUEST (sampling/roots/elicitation): answer
            # immediately with a JSON-RPC error so servers never hang on us.
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
            } except Exception {
            }
            continue;
        }
        if rid is not None and method is None {
            # Response to one of ours: correlate by id.
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
        # True notification: buffer for the session dispatcher (bounded).
        if len(client.notifications) < MAX_NOTIFICATIONS {
            client.notifications.append(parsed);
        }
    }
    # EOF while the client still wanted reads: record unexpected death and
    # fail every in-flight waiter fast instead of burning their timeouts.
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


def _start_reader(client: McpClient) {
    _ensure_io(client);
    if client.reader_thread is not None and client.reader_thread.is_alive() {
        return;
    }
    client.reader_stop.clear();
    t = threading.Thread(
        target=_reader_loop, args=(client,), daemon=True, name="mcp-reader"
    );
    client.reader_thread = t;
    t.start();
}


def _stop_reader(client: McpClient) {
    if client.reader_stop is not None {
        client.reader_stop.set();
    }
    client.reader_thread = None;
}


def _write_line(client: McpClient, msg: dict[str, any]) {
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


"""Send a JSON-RPC request and wait for the correlated response.

Internal: raises TimeoutError/RuntimeError. Public seam wraps this."""
def _request(client: McpClient, method: str, params: dict[str, any], timeout_s: float) -> dict[str, any] {
    _ensure_io(client);
    rid = client.next_id;
    client.next_id += 1;
    key = str(rid);
    client.pending[key] = {"event": threading.Event(), "msg": None};
    req: dict[str, any] = {
        "jsonrpc": "2.0",
        "id": rid,
        "method": method,
        "params": params if params else {},
    };
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
            return got as dict;
        }
        if waiter.get("eof") {
            # Reader hit EOF: the server is gone — fail fast, honestly.
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
"""Extract {"ok": ...} payload from a JSON-RPC response dict."""
def _response_payload(resp: dict[str, any]) -> dict[str, any] {
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


def _effective_timeout(client: McpClient, timeout_s: float) -> float {
    if timeout_s > 0.0 {
        return timeout_s;
    }
    return client.timeout_s;
}


"""Spawn the MCP server subprocess and run the initialize handshake.

server_cmd example: ["jac", "mcp"]. env_extra merges over os.environ for the
child; cwd sets the child working directory ("" = inherit). Returns
{"ok": True, "server_info": ...} or {"ok": False, "error": ...}; never
raises."""
def mcp_start(
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
    # env_extra merges over the inherited environment (Popen env=None would
    # mean "inherit everything, change nothing"); cwd="" keeps inheritance.
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
        "capabilities": {},
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
    # Handshake completion notification (no response expected).
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


"""List tools exposed by the server, following nextCursor pagination
(capped at MAX_LIST_PAGES so a broken cursor cannot loop forever).
Returns {"ok", "tools": [...]} with all pages merged."""
def mcp_list_tools(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
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


"""Call a tool on the server. Returns {"ok", "result", "is_error"?, ...}.

Text content blocks join into "result"; image/audio/resource/resource_link
blocks render as honest text stubs in "result" and are preserved raw under
"content". MCP-level tool failures (isError=true) come back ok=True with
is_error=True and the error text in "result" — the transport succeeded;
semantics failed."""
def mcp_call_tool(
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
    # Flatten content blocks: text joins directly; non-text blocks become
    # honest text stubs (never dropped silently) and the raw blocks ride
    # along under "content" for richer plumbing later.
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
                    "[image: " + str(block.get("mimeType", "unknown"))
                    + ", " + str(len(str(block.get("data", "")))) + " b64 chars]"
                );
            } elif btype == "audio" {
                parts.append(
                    "[audio: " + str(block.get("mimeType", "unknown"))
                    + ", " + str(len(str(block.get("data", "")))) + " b64 chars]"
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
                parts.append("[unsupported content block: " + (btype if btype else "unknown") + "]");
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


"""Stop the server subprocess and tear down reader state. Never raises."""
def mcp_stop(client: McpClient) -> dict[str, any] {
    proc = client.proc;
    if proc is not None {
        try {
            if proc.poll() is None {
                if proc.stdin is not None {
                    try {
                        proc.stdin.close();
                    } except Exception {
                    }
                }
                proc.terminate();
                try {
                    proc.wait(timeout=2.0);
                } except Exception {
                    try {
                        proc.kill();
                        proc.wait(timeout=2.0);
                    } except Exception {
                    }
                }
            }
        } except Exception {
        }
    }
    _stop_reader(client);
    client.proc = None;
    client.initialized = False;
    client.pending = {};
    return {"ok": True};
}


"""Map MCP tools/list results to ToolSpec-compatible dicts.

Each spec matches the native registration shape used across the repo:
{"name", "description", "parameters"} where parameters is the MCP
inputSchema JSON-Schema dict (empty object schema when absent).
prefix avoids collisions with native tools (e.g. "mcp_")."""
def mcp_tool_specs(client: McpClient, prefix: str = "", timeout_s: float = -1.0) -> list[dict[str, any]] {
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


"""Public liveness: process running and no unexpected EOF observed."""
def mcp_is_alive(client: McpClient) -> bool {
    return _alive(client) and not client.dead;
}


"""Pop and return all buffered server notifications (the reader keeps the
buffer bounded); the session dispatcher consumes the result."""
def mcp_drain_notifications(client: McpClient) -> list[dict[str, any]] {
    out: list[dict[str, any]] = list(client.notifications);
    client.notifications.clear();
    return out;
}

"""List prompts exposed by the server (pagination-aware, capped like
tools/list). Returns {"ok", "prompts": [{name, description, arguments}]}."""
def mcp_list_prompts(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
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


"""Fetch one prompt's messages. Returns
{"ok", "description", "messages": [{role, content}, ...]}."""
def mcp_get_prompt(
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


"""List resources exposed by the server (pagination-aware, capped like
tools/list). Returns {"ok", "resources": [{uri, name, description,
mimeType}]}. Servers without the resources capability come back ok False
(method not found) — callers treat that as an absent capability, not an
error."""
def mcp_list_resources(client: McpClient, timeout_s: float = -1.0) -> dict[str, any] {
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


"""Read one resource by URI. Text contents join into "text"; blob contents
render as an honest stub line (never dropped). Returns {"ok", "uri",
"text", "contents"} with the raw contents riding along."""
def mcp_read_resource(client: McpClient, uri: str, timeout_s: float = -1.0) -> dict[str, any] {
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
