"""MCP client — talks to `jac mcp` (or any MCP server) as a stdio subprocess,
or to a remote server over streamable HTTP.

Transports: (stdio) newline-delimited JSON-RPC 2.0 over stdin/stdout
(verified against `jac mcp`, which speaks one JSON object per line, no
Content-Length framing); (http) streamable-HTTP — each request is a POST,
responses come back as JSON or a text/event-stream body (parsed until the
correlated response), the Mcp-Session-Id from initialize is echoed on every
call, and no GET listener stream is opened. Lifecycle: start -> initialize
handshake -> notifications/initialized -> tools/list / tools/call -> stop.

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
import from http.client { HTTPResponse }
import from _subprocess_native { sp_close, sp_env_strings, sp_read, sp_write }
import urllib.request;
import from urllib.request { Request }

glob DEFAULT_TIMEOUT_S: float = 15.0,
     MAX_NOTIFICATIONS: int = 1000,
     MAX_LIST_PAGES: int = 64;

# Protocol version we offer during initialize; servers negotiate down.
glob MCP_PROTOCOL_VERSION: str = "2025-06-18";


obj McpPending {
    has event: threading.Event = threading.Event(),
        msg: dict[str, any] | None = None,
        eof: bool = False;
}


obj:pub McpClient {
    """State holder for one MCP server subprocess."""
    has dead: bool = False,
        proc: subprocess.Popen | None = None,
        server_cmd: list[str] = [],
        next_id: int = 1,
        timeout_s: float = DEFAULT_TIMEOUT_S,
        initialized: bool = False,
        protocol_version: str = "",
        server_info: dict[str, any] = {},
        pending: dict[str, McpPending] = {},
        notifications: list[dict[str, any]] = [],
        reader_buffer: bytes = b"",
        write_lock: threading.Lock | None = None,
        reader_stop: threading.Event | None = None,
        reader_thread: threading.Thread | None = None,
        # Server-initiated request handler (stdio): fn(method, params) ->
        # {"ok": True, "result": dict} | {"ok": False, "code": int,
        # "message": str}. Runs on a short-lived daemon thread, NEVER on
        # the reader thread; None keeps the legacy -32601 reply for every
        # inbound request.
        on_request: Callable[[str, dict[str, any]], dict[str, any]] | None = None,
        # streamable-HTTP transport state (transport: "stdio" | "http")
        transport: str = "stdio",
        url: str = "",
        headers: dict[str, str] = {},
        session_id: str = "";

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
    if client.transport == "http" {
        return client.initialized and not client.dead;
    }
    proc: subprocess.Popen | None = client.proc;
    if proc is None {
        return False;
    }
    return proc.poll() is None;
}


def _ensure_io(client: McpClient) -> None {
    if client.write_lock is None {
        client.write_lock = threading.Lock();
    }
    if client.reader_stop is None {
        client.reader_stop = threading.Event();
    }
}


def _start_inbound_worker(
    client: McpClient,
    rid: any,
    method: str,
    params: dict[str, any],
) {
    def serve_inbound() {
        _serve_inbound(client, rid, method, params);
    }
    t = threading.Thread(
        target=serve_inbound,
        daemon=True,
        name="mcp-inbound",
    );
    t.start();
}


"""Background stdout reader — routes responses by id, buffers notifications."""
def _reader_loop(client: McpClient) {
    stop = client.reader_stop;
    proc: subprocess.Popen | None = client.proc;
    if proc is None or proc._stdout_r < 0 {
        return;
    }
    while stop is None or not stop.is_set() {
        try {
            line_raw: bytes = _read_process_line(client, proc._stdout_r);
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
        parsed_msg: dict[str, any] = parsed as dict[str, any];
        rid: any = parsed_msg.get("id");
        method: any = parsed_msg.get("method");
        if rid is not None and method is not None {
            # Server->client REQUEST (sampling/elicitation/roots). With a
            # registered handler, hand off to a short-lived daemon thread
            # so the reader never blocks on UI/model work; the serve
            # thread owns writing the exactly-one reply. Without one, keep
            # the legacy bounded answer: a JSON-RPC error, never silence.
            handler: Callable[[str, dict[str, any]], dict[str, any]] | None = client.on_request;
            if handler is not None {
                raw_params: any = parsed_msg.get("params");
                p_in: dict[str, any] = raw_params if isinstance(raw_params, dict) else {};
                _start_inbound_worker(client, rid, str(method), p_in);
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
                } except Exception {
                }
            }
            continue;
        }
        if rid is not None and method is None {
            # Response to one of ours: correlate by id.
            key = str(rid);
            waiter: McpPending | None = client.pending.get(key);
            if waiter is not None {
                waiter.msg = parsed_msg;
                waiter.event.set();
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
        if leftover.msg is None {
            leftover.eof = True;
            leftover.event.set();
        }
    }
}


def _read_process_line(client: McpClient, fd: int) -> bytes {
    newline: int = client.reader_buffer.find(b"\n");
    while newline < 0 {
        chunk: bytes = sp_read(fd, 4096);
        if not chunk {
            line: bytes = client.reader_buffer;
            client.reader_buffer = b"";
            return line;
        }
        client.reader_buffer += chunk;
        newline = client.reader_buffer.find(b"\n");
    }
    end: int = newline + 1;
    line2: bytes = client.reader_buffer[:end];
    client.reader_buffer = client.reader_buffer[end:];
    return line2;
}


"""POST one JSON-RPC message over streamable HTTP and return the response
dict for the correlated id. JSON bodies parse directly; text/event-stream
bodies are parsed until the correlated response event (notifications seen
on the stream are buffered, bounded); 202 / expect_body=False returns None.
HTTP 4xx with a JSON-RPC error body surfaces as a normal response; 404 and
5xx mark the client dead (session gone / server error) so health and revive
machinery see it. Raises RuntimeError/TimeoutError."""
def _http_exchange(
    client: McpClient,
    msg: dict[str, any],
    timeout_s: float,
    expect_body: bool,
) -> (dict[str, any] | None) {
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
    req: Request = urllib.request.Request(
        client.url, data=body, headers=hdrs, method="POST"
    );
    resp: HTTPResponse | None = None;
    try {
        resp = urllib.request.urlopen(req, timeout=timeout_s) as HTTPResponse;
    } except TimeoutError {
        raise TimeoutError(f"http request timed out after {timeout_s}s");
    } except OSError as ue {
        client.dead = True;
        raise RuntimeError(f"http transport failed: {ue}");
    }
    if resp is None {
        raise RuntimeError("mcp HTTP transport returned no response");
    }
    try {
        sid: str = str(resp.headers.get("mcp-session-id", "") or "");
        if sid and not client.session_id {
            client.session_id = str(sid);
        }
        status: int = int(resp.status);
        if status == 202 or not expect_body {
            return None;
        }
        ctype: str = str(resp.headers.get("content-type", "") or "");
        if ctype.startswith("text/event-stream") {
            # Streamable HTTP: the response may ride as SSE events; parse
            # until the correlated response arrives, buffering anything
            # else (notifications, server requests) bounded like stdio.
            while True {
                line_raw: bytes | str = resp.readline();
                if not line_raw {
                    break;
                }
                line_s: str = (
                    line_raw.decode("utf-8")
                    if isinstance(line_raw, bytes)
                    else line_raw
                ).strip();
                if not line_s {
                    continue;
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
                if isinstance(got, dict) {
                    got_obj: dict[str, any] = got as dict[str, any];
                    if got_obj.get("id") == msg.get("id") and "method" not in got_obj {
                        return got_obj;
                    }
                    if len(client.notifications) < MAX_NOTIFICATIONS {
                        client.notifications.append(got_obj);
                    }
                }
            }
            return {
                "jsonrpc": "2.0",
                "id": msg.get("id"),
                "error": {"code": -32000, "message": "sse stream ended without a response"},
            };
        }
        raw2: bytes = resp.read();
        parsed2: any = None;
        try {
            parsed2 = json.loads(raw2.decode("utf-8", "replace"));
        } except Exception {
            if status == 404 or status >= 500 {
                client.dead = True;
                raise RuntimeError(f"http {status} from mcp server");
            }
            raise;
        }
        if isinstance(parsed2, dict) {
            return parsed2 as dict[str, any];
        }
        if status == 404 or status >= 500 {
            client.dead = True;
            raise RuntimeError(f"http {status} from mcp server");
        }
        raise RuntimeError("mcp server returned a non-object response");
    } finally {
        try {
            resp.close();
        } except Exception {
        }
    }
}


def _start_reader(client: McpClient) -> None {
    _ensure_io(client);
    if client.reader_thread is not None and client.reader_thread.is_alive() {
        return;
    }
    reader_stop: threading.Event | None = client.reader_stop;
    if reader_stop is not None {
        reader_stop.clear();
    }
    def read_client() {
        _reader_loop(client);
    }
    t: threading.Thread = threading.Thread(
        target=read_client, daemon=True, name="mcp-reader"
    );
    client.reader_thread = t;
    t.start();
}


def _stop_reader(client: McpClient) -> None {
    if client.reader_stop is not None {
        client.reader_stop.set();
    }
    client.reader_thread = None;
}


def _write_line(client: McpClient, msg: dict[str, any]) {
    if client.transport == "http" {
        # Streamable HTTP: client->server notifications are fire-and-forget
        # POSTs (202 expected, no body).
        _http_exchange(client, msg, client.timeout_s, False);
        return;
    }
    proc: subprocess.Popen | None = client.proc;
    if not _alive(client) or proc is None or proc._stdin_w < 0 {
        raise RuntimeError("mcp server not running");
    }
    line: bytes = (json.dumps(msg) + "\n").encode("utf-8");
    lock: threading.Lock | None = client.write_lock;
    if lock is not None {
        lock.acquire();
        try {
            _write_process_bytes(proc._stdin_w, line);
        } finally {
            lock.release();
        }
    } else {
        _write_process_bytes(proc._stdin_w, line);
    }
}


def _write_process_bytes(fd: int, data: bytes) -> None {
    off: int = 0;
    while off < len(data) {
        wrote: int = sp_write(fd, data[off:]);
        if wrote <= 0 {
            raise RuntimeError("mcp process pipe write failed");
        }
        off += wrote;
    }
}


"""Send a JSON-RPC request and wait for the correlated response.

Internal: raises TimeoutError/RuntimeError. Public seam wraps this."""
def _request(client: McpClient, method: str, params: dict[str, any], timeout_s: float) -> dict[str, any] {
    if client.transport == "http" {
        rid_h: int = client.next_id;
        client.next_id += 1;
        req_h: dict[str, any] = {
            "jsonrpc": "2.0",
            "id": rid_h,
            "method": method,
            "params": params if params else {},
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
        return got_h as dict;
    }
    _ensure_io(client);
    rid = client.next_id;
    client.next_id += 1;
    key = str(rid);
    client.pending[key] = McpPending();
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
        waiter: McpPending | None = client.pending.get(key);
        if waiter is None {
            raise RuntimeError("mcp response waiter vanished");
        }
        if waiter.msg is not None {
            client.pending.pop(key, None);
            return waiter.msg;
        }
        if waiter.eof {
            # Reader hit EOF: the server is gone — fail fast, honestly.
            client.pending.pop(key, None);
            raise RuntimeError("mcp server closed connection");
        }
        ok = waiter.event.wait(timeout=remaining);
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
    popen_env: dict[str, str] | None = None;
    if env_extra {
        base_env: dict[str, str] = {};
        for env_line in sp_env_strings() {
            sep: int = env_line.find("=");
            if sep > 0 {
                env_key: str = env_line[:sep];
                base_env[env_key] = env_line[sep + 1:];
            }
        }
        for (env_k, env_v) in env_extra.items() {
            base_env[str(env_k)] = str(env_v);
        }
        popen_env = base_env;
    }
    popen_cwd: str | None = None;
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
        # Inbound capabilities: this client can serve sampling and
        # elicitation requests over the stdio transport (dispatched via
        # the registered on_request handler; see mcp_set_request_handler).
        # HTTP stays {} — no inbound listener exists there.
        "capabilities": {"sampling": {}, "elicitation": {}},
        "clientInfo": {"name": "jackal", "version": "0.1.0"},
    };
    try {
        resp = _request(client, "initialize", init_params, timeout);
    } except Exception as e {
        mcp_stop(client);
        return {"ok": False, "error": f"initialize failed: {e}"};
    }
    payload: dict[str, any] = _response_payload(resp);
    if not payload["ok"] {
        mcp_stop(client);
        return payload;
    }
    result: dict[str, any] = payload["result"] as dict[str, any];
    pv: str = str(result.get("protocolVersion", ""));
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


"""Connect to a streamable-HTTP MCP server and run the initialize
handshake (no subprocess, no reader thread). url: the server endpoint
(http:// or https://); headers: static extra headers such as
Authorization. The Mcp-Session-Id issued on initialize is captured and
echoed on every later request. Returns the same shape as mcp_start; never
raises."""
def mcp_start_http(
    client: McpClient,
    url: str,
    headers: dict[str, str] | None = None,
    timeout_s: float = -1.0,
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
    payload: dict[str, any] = _response_payload(resp);
    if not payload["ok"] {
        return payload;
    }
    result: dict[str, any] = payload["result"] as dict[str, any];
    pv: str = str(result.get("protocolVersion", ""));
    if pv {
        client.protocol_version = pv;
    }
    raw_info: any = result.get("serverInfo");
    info: dict[str, any] = {};
    if isinstance(raw_info, dict) {
        info = raw_info;
    }
    client.server_info = info;
    # Handshake completion notification (fire-and-forget POST).
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
        result: dict[str, any] = payload["result"] as dict[str, any];
        raw_tools: any = result.get("tools", []);
        if isinstance(raw_tools, list) {
            tool_values: list[any] = raw_tools as list[any];
            for raw_tool in tool_values {
                if isinstance(raw_tool, dict) {
                    t: dict[str, any] = raw_tool as dict[str, any];
                    if not t.get("name") {
                        continue;
                    }
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
    result: dict[str, any] = payload["result"] as dict[str, any];
    # Flatten content blocks: text joins directly; non-text blocks become
    # honest text stubs (never dropped silently) and the raw blocks ride
    # along under "content" for richer plumbing later.
    parts: list[str] = [];
    raw_content: any = result.get("content", []);
    blocks: list[dict[str, any]] = [];
    if isinstance(raw_content, list) {
        content_values: list[any] = raw_content as list[any];
        for raw_block in content_values {
            if not isinstance(raw_block, dict) {
                continue;
            }
            block: dict[str, any] = raw_block as dict[str, any];
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
                raw_resource: any = block.get("resource");
                if isinstance(raw_resource, dict) {
                    res: dict[str, any] = raw_resource as dict[str, any];
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
    if client.transport == "http" {
        # Best-effort session teardown (DELETE), then reset state. The
        # notification buffer stays drained by the session dispatcher.
        if client.session_id {
            try {
                hdrs: dict[str, str] = dict(client.headers);
                hdrs["Mcp-Session-Id"] = client.session_id;
                req: Request = urllib.request.Request(
                    client.url, data=b"", headers=hdrs, method="DELETE"
                );
                resp: HTTPResponse = urllib.request.urlopen(
                    req, timeout=2.0
                ) as HTTPResponse;
                try {
                    resp.close();
                } except Exception {
                }
            } except Exception {
            }
        }
        client.initialized = False;
        client.session_id = "";
        client.pending = {};
        return {"ok": True};
    }
    proc: subprocess.Popen | None = client.proc;
    if proc is not None {
        try {
            if proc._stdin_w >= 0 {
                sp_close(proc._stdin_w);
                proc._stdin_w = -1;
            }
            if proc.poll() is None {
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
        if proc._stdout_r >= 0 {
            sp_close(proc._stdout_r);
            proc._stdout_r = -1;
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
    raw_tools: any = res.get("tools", []);
    if not isinstance(raw_tools, list) {
        return specs;
    }
    tools: list[any] = raw_tools as list[any];
    for raw_tool in tools {
        if not isinstance(raw_tool, dict) {
            continue;
        }
        t: dict[str, any] = raw_tool as dict[str, any];
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
        result: dict[str, any] = payload["result"] as dict[str, any];
        raw_prompts: any = result.get("prompts", []);
        if isinstance(raw_prompts, list) {
            prompt_values: list[any] = raw_prompts as list[any];
            for raw_prompt in prompt_values {
                if isinstance(raw_prompt, dict) {
                    pr: dict[str, any] = raw_prompt as dict[str, any];
                    if not pr.get("name") {
                        continue;
                    }
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
    result: dict[str, any] = payload["result"] as dict[str, any];
    messages: list[dict[str, any]] = [];
    raw_msgs: any = result.get("messages", []);
    if isinstance(raw_msgs, list) {
        message_values: list[any] = raw_msgs as list[any];
        for raw_message in message_values {
            if isinstance(raw_message, dict) {
                messages.append(raw_message as dict[str, any]);
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
        result: dict[str, any] = payload["result"] as dict[str, any];
        raw_res: any = result.get("resources", []);
        if isinstance(raw_res, list) {
            resource_values: list[any] = raw_res as list[any];
            for raw_resource in resource_values {
                if isinstance(raw_resource, dict) {
                    r: dict[str, any] = raw_resource as dict[str, any];
                    if not r.get("uri") {
                        continue;
                    }
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
    result: dict[str, any] = payload["result"] as dict[str, any];
    parts: list[str] = [];
    contents: list[dict[str, any]] = [];
    raw_contents: any = result.get("contents", []);
    if isinstance(raw_contents, list) {
        content_values: list[any] = raw_contents as list[any];
        for raw_content in content_values {
            if not isinstance(raw_content, dict) {
                continue;
            }
            c: dict[str, any] = raw_content as dict[str, any];
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


"""Serve one inbound server->client request on its own daemon thread.

Calls the registered handler (never the reader thread) and writes the
exactly-one JSON-RPC reply: result on ok, the handler's error code/message
otherwise, -32603 if the handler raised or returned a malformed verdict.
A write failure (dead transport) drops the reply — the server's own
request timeout is the backstop. Never raises."""
def _serve_inbound(client: McpClient, rid: any, method: str, params: dict[str, any]) {
    reply: dict[str, any] = {
        "jsonrpc": "2.0",
        "id": rid,
        "error": {"code": -32603, "message": "client handler failed"},
    };
    try {
        handler: Callable[[str, dict[str, any]], dict[str, any]] | None = client.on_request;
        verdict: dict[str, any] | None = None;
        if handler is not None {
            verdict = handler(method, params);
        }
        code_i: int = -32000;
        if verdict is not None {
            try {
                code_i = int(verdict.get("code", -32000));
            } except Exception {
                code_i = -32000;
            }
        }
        if verdict is not None and bool(verdict.get("ok", False)) {
            res: any = verdict.get("result");
            reply = {
                "jsonrpc": "2.0",
                "id": rid,
                "result": res if isinstance(res, dict) else {},
            };
        } elif verdict is not None {
            reply = {
                "jsonrpc": "2.0",
                "id": rid,
                "error": {
                    "code": code_i,
                    "message": str(verdict.get("message", "request failed")),
                },
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
    } except Exception {
    }
}


"""Register the server-initiated request handler (stdio transport).

Contract: fn(method, params) -> {"ok": True, "result": dict} on success,
or {"ok": False, "code": int, "message": str} to answer with a JSON-RPC
error (use -32601 for methods this client does not support). The handler
runs on a dedicated daemon thread per request — it may block on UI or the
model, but it must eventually return; the server's request timeout is the
only backstop if it does not. HTTP clients have no inbound listener and
ignore this seam."""
def mcp_set_request_handler(
    client: McpClient,
    handler: Callable[[str, dict[str, any]], dict[str, any]] | None,
) -> None {
    client.on_request = handler;
}
