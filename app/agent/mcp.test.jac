"""Tests for agent/mcp.jac (same-stem annex, merged with the base module
at test time - no import of the own stem). All transport tests run against
a fake newline-delimited JSON-RPC MCP server generated into a temp dir at
test time; the real `jac mcp` is never spawned here.

Fake server modes:
  normal   - handshake + echo/boom tools (transport basics)
  silent   - never answers tools/list (timeout path)
  paged    - tools/list pages 5 tools two at a time via nextCursor
  requests - sends sampling/roots server->client requests before tools/list;
             the listed tool name proves whether the client answered them
  dieafter - exits immediately after the initialized notification (EOF path)

A second fixture (FAKE_HTTP_SERVER_SRC) is a streamable-HTTP MCP server:
initialize issues Mcp-Session-Id sess-42 and post-initialize requests
without that header are rejected, tools/list answers as JSON, tools/call
answers as text/event-stream (both client response paths).
"""

glob FAKE_SERVER_SRC: str = """
import sys, json, time, os

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\\n")
    sys.stdout.flush()

mode = sys.argv[1] if len(sys.argv) > 1 else "normal"

def read_replies(want_ids, deadline):
    # Plain blocking readline (no select): the stdin iterator readahead can
    # park bytes in the userspace buffer where select cannot see them. The
    # client under test always answers or its own request timeout fires.
    got = {}
    while len(got) < len(want_ids) and time.time() < deadline:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        mid = msg.get("id")
        if mid in want_ids and "error" in msg:
            got[mid] = msg["error"]
    return got

PAGE_TOOLS = [
    {"name": "t%d" % i, "description": "page tool %d" % i,
     "inputSchema": {"type": "object", "properties": {}, "required": []}}
    for i in range(5)
]

for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        req = json.loads(raw)
    except Exception:
        continue
    method = req.get("method", "")
    rid = req.get("id")
    if mode == "silent" and method == "tools/list":
        continue  # silent: never respond (timeout path)
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "fake-mcp", "version": "0.0.1"},
        }})
    elif method == "notifications/initialized":
        if mode == "dieafter":
            os._exit(1)
    elif method == "tools/list":
        if mode == "paged":
            cursor = str((req.get("params") or {}).get("cursor", ""))
            start = int(cursor) if cursor.isdigit() else 0
            page = PAGE_TOOLS[start:start + 2]
            result = {"tools": page}
            if start + 2 < len(PAGE_TOOLS):
                result["nextCursor"] = str(start + 2)
            send({"jsonrpc": "2.0", "id": rid, "result": result})
        elif mode == "requests":
            # Server->client requests: a compliant client answers each with
            # a JSON-RPC error instead of leaving them hanging.
            send({"jsonrpc": "2.0", "id": "s1", "method": "sampling/createMessage",
                  "params": {"messages": []}})
            send({"jsonrpc": "2.0", "id": "s2", "method": "roots/list", "params": {}})
            errs = read_replies(["s1", "s2"], time.time() + 5.0)
            ok = len(errs) == 2 and all(
                e.get("code") == -32601 for e in errs.values())
            send({"jsonrpc": "2.0", "id": rid, "result": {"tools": [
                {"name": "ok_ping" if ok else "bad_no_reply",
                 "description": "probe",
                 "inputSchema": {"type": "object", "properties": {},
                                 "required": []}}]}})
        else:
            send({"jsonrpc": "2.0", "id": rid, "result": {"tools": [
                {"name": "echo", "description": "Echo the given text back.",
                 "inputSchema": {"type": "object",
                                 "properties": {"text": {"type": "string"}},
                                 "required": ["text"]}},
                {"name": "boom", "description": "Always fails.",
                 "inputSchema": {"type": "object",
                                 "properties": {}, "required": []}},
                {"name": "rich", "description": "Returns mixed content blocks.",
                 "inputSchema": {"type": "object",
                                 "properties": {}, "required": []}},
            ]}})
    elif method == "prompts/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"prompts": [
            {"name": "greet", "description": "Greet someone.",
             "arguments": [{"name": "who", "required": False}]},
        ]}})
    elif method == "prompts/get":
        pname = str(req.get("params", {}).get("name", ""))
        if pname != "greet":
            send({"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32602, "message": "unknown prompt"}})
            continue
        who = str(req.get("params", {}).get("arguments", {}).get("who", "world"))
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "description": "A greeting",
            "messages": [
                {"role": "user", "content": {"type": "text",
                                             "text": "Hello, " + who + "!"}},
            ]}})
    elif method == "resources/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"resources": [
            {"uri": "mem://notes/1", "name": "notes", "description": "First note.",
             "mimeType": "text/plain"},
            {"uri": "mem://bin/1", "name": "blobby", "mimeType": "application/octet-stream"},
        ]}})
    elif method == "resources/read":
        uri = str((req.get("params") or {}).get("uri", ""))
        if uri == "mem://notes/1":
            send({"jsonrpc": "2.0", "id": rid, "result": {"contents": [
                {"uri": uri, "mimeType": "text/plain", "text": "resource one"}]}})
        elif uri == "mem://bin/1":
            send({"jsonrpc": "2.0", "id": rid, "result": {"contents": [
                {"uri": uri, "mimeType": "application/octet-stream", "blob": "QUJD"}]}})
        else:
            send({"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32602, "message": "unknown resource"}})
    elif method == "tools/call":
        name = str(req.get("params", {}).get("name", ""))
        args = req.get("params", {}).get("arguments", {}) or {}
        if name == "echo":
            text = str(args.get("text", ""))
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": "echo:" + text}],
                "isError": False}})
        elif name == "rich":
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "content": [
                    {"type": "image", "data": "aGVsbG8=",
                     "mimeType": "image/png"},
                    {"type": "resource", "resource": {
                        "uri": "file:///x.txt", "mimeType": "text/plain",
                        "text": "resource body"}},
                    {"type": "resource_link", "uri": "file:///y.txt"},
                ],
                "isError": False}})
        else:
            send({"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601, "message": "unknown tool: " + name}})
    elif rid is not None:
        send({"jsonrpc": "2.0", "id": rid, "error": {
            "code": -32601, "message": "method not found"}})
""";


def _write_mode_server(tmp: str, mode: str) -> list[str] {
    path = os.path.join(tmp, "mcp_server_" + mode + ".py");
    with open(path, "w") as f { f.write(FAKE_SERVER_SRC); }
    return [sys.executable, path, mode];
}


def _write_fake_server(tmp: str) -> list[str] {
    return _write_mode_server(tmp, "normal");
}


def _write_silent_server(tmp: str) -> list[str] {
    return _write_mode_server(tmp, "silent");
}


test "start handshake and stop against fake mcp server" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        res = mcp_start(client, cmd, timeout_s=10.0);
        assert res["ok"] is True;
        assert res.get("server_name") == "fake-mcp";
        assert client.initialized is True;
        assert client.protocol_version == "2025-06-18";
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "tools/list maps to ToolSpec-shaped specs" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        specs = mcp_tool_specs(client);
        assert len(specs) == 3;
        echo: any = None;
        for s in specs {
            if s["name"] == "echo" { echo = s; }
        }
        assert echo is not None;
        assert echo["description"] == "Echo the given text back.";
        props: any = echo["parameters"].get("properties");
        assert isinstance(props, dict) and "text" in props;
        # prefixed mapping avoids native-tool collisions
        prefixed = mcp_tool_specs(client, prefix="mcp_");
        names = [s["name"] for s in prefixed];
        assert "mcp_echo" in names;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "tools/list follows nextCursor pagination to exhaustion" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_mode_server(tmp, "paged");
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        res = mcp_list_tools(client, timeout_s=10.0);
        assert res["ok"] is True;
        tools: any = res.get("tools", []);
        names = [str(t.get("name", "")) for t in tools];
        # 5 tools across 3 pages (2+2+1) — no silent truncation.
        assert len(names) == 5;
        for i in range(5) {
            assert ("t" + str(i)) in names;
        }
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "server-to-client requests are answered, never buffered" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_mode_server(tmp, "requests");
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        res = mcp_list_tools(client, timeout_s=10.0);
        assert res["ok"] is True;
        tools: any = res.get("tools", []);
        # The server names its only tool after what it observed: ok_ping
        # means the client answered sampling/roots with method errors.
        names = [str(t.get("name", "")) for t in tools];
        assert "ok_ping" in names, names;
        # And the requests were never buffered as notifications.
        for note in client.notifications {
            assert str(note.get("method", "")) != "sampling/createMessage";
        }
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "call_tool round trip through fake server" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        res = mcp_call_tool(client, "echo", {"text": "hello"}, timeout_s=10.0);
        assert res["ok"] is True;
        assert res.get("is_error") is False;
        assert res.get("result") == "echo:hello";
        # JSON-RPC-level error for unknown tool fails loud at the seam
        bad = mcp_call_tool(client, "nope", {}, timeout_s=10.0);
        assert bad["ok"] is False;
        assert "unknown tool" in str(bad.get("error", ""));
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "timeout on silent tools/list returns ok False" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_silent_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        t0 = time.time();
        res = mcp_list_tools(client, timeout_s=0.5);
        elapsed = time.time() - t0;
        assert res["ok"] is False;
        assert "timed out" in str(res.get("error", ""));
        assert elapsed < 5.0;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "server death fails in-flight calls fast and marks the client dead" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_mode_server(tmp, "dieafter");
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        # Give the server a moment to exit after the initialized notification.
        time.sleep(0.3);
        t0 = time.time();
        res = mcp_list_tools(client, timeout_s=10.0);
        elapsed = time.time() - t0;
        assert res["ok"] is False;
        # EOF fast-fail (closed connection) or honest not-running — never a
        # full 10s timeout burn.
        assert elapsed < 5.0;
        assert mcp_is_alive(client) is False;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "spawn failure and empty-cmd fail loud without raising" {
    client = create_mcp_client();
    res = mcp_start(client, ["/nonexistent/jackal/fake_binary_xyz"], timeout_s=5.0);
    assert res["ok"] is False;
    assert "failed to spawn" in str(res.get("error", ""));
    empty = mcp_start(client, []);
    assert empty["ok"] is False;
    # calls before start also fail loud
    fresh = create_mcp_client();
    lt = mcp_list_tools(fresh);
    assert lt["ok"] is False;
    ct = mcp_call_tool(fresh, "x", {});
    assert ct["ok"] is False;
}

test "non-text content blocks surface as stubs and ride along raw" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        res = mcp_call_tool(client, "rich", {}, timeout_s=10.0);
        assert res["ok"] is True;
        text: str = str(res.get("result", ""));
        assert "[image: image/png, 8 b64 chars]" in text, text;
        assert "[resource: file:///x.txt text/plain]" in text, text;
        assert "resource body" in text, text;
        assert "[resource_link: file:///y.txt]" in text, text;
        blocks: any = res.get("content", []);
        assert isinstance(blocks, list) and len(blocks) == 3;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}

test "prompts list and get round trip" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        listed = mcp_list_prompts(client, timeout_s=10.0);
        assert listed["ok"] is True;
        prompts: any = listed.get("prompts", []);
        assert len(prompts) == 1;
        assert str(prompts[0]["name"]) == "greet";
        got = mcp_get_prompt(client, "greet", {"who": "jackal"}, timeout_s=10.0);
        assert got["ok"] is True;
        assert str(got.get("description", "")) == "A greeting";
        msgs: any = got.get("messages", []);
        assert len(msgs) == 1;
        text: str = str(msgs[0].get("content", {}).get("text", ""));
        assert text == "Hello, jackal!", text;
        # unknown prompt -> honest error at the seam
        bad = mcp_get_prompt(client, "nope", {}, timeout_s=10.0);
        assert bad["ok"] is False;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "resources list and read round trip" {
    tmp = tempfile.mkdtemp();
    client = create_mcp_client();
    try {
        cmd = _write_fake_server(tmp);
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        listed = mcp_list_resources(client, timeout_s=10.0);
        assert listed["ok"] is True;
        res: any = listed.get("resources", []);
        assert len(res) == 2;
        assert str(res[0]["uri"]) == "mem://notes/1";
        assert str(res[0]["name"]) == "notes";
        assert str(res[1]["mimeType"]) == "application/octet-stream";
        # text content joins into "text", raw contents ride along
        got = mcp_read_resource(client, "mem://notes/1", timeout_s=10.0);
        assert got["ok"] is True;
        assert str(got.get("text", "")) == "resource one";
        contents: any = got.get("contents", []);
        assert isinstance(contents, list) and len(contents) == 1;
        # blob content surfaces as an honest stub, never dropped
        blob = mcp_read_resource(client, "mem://bin/1", timeout_s=10.0);
        assert blob["ok"] is True;
        assert "[blob resource: application/octet-stream, 4 b64 chars]" in str(blob.get("text", ""));
        # unknown uri -> honest JSON-RPC error at the seam
        bad = mcp_read_resource(client, "mem://nope", timeout_s=10.0);
        assert bad["ok"] is False;
        assert "unknown resource" in str(bad.get("error", ""));
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


glob FAKE_HTTP_SERVER_SRC: str = """
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SID = "sess-42"
TOOLS = [{"name": "echo", "description": "Echo the given text back.",
          "inputSchema": {"type": "object",
                          "properties": {"text": {"type": "string"}},
                          "required": ["text"]}}]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj, extra=None):
        payload = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        method = req.get("method", "")
        rid = req.get("id")
        if method == "initialize":
            self._json(200, {"jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fake-http-mcp", "version": "0"}}},
                {"Mcp-Session-Id": SID})
        elif method.startswith("notifications/"):
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.headers.get("Mcp-Session-Id") != SID:
            self._json(400, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32001, "message": "missing or stale session id"}})
        elif method == "tools/list":
            self._json(200, {"jsonrpc": "2.0", "id": rid, "result": {"tools": TOOLS}})
        elif method == "tools/call":
            nm = str(req.get("params", {}).get("name", ""))
            if nm != "echo":
                self._json(200, {"jsonrpc": "2.0", "id": rid, "error": {
                    "code": -32601, "message": "method not found"}})
                return
            text = str(req.get("params", {}).get("arguments", {}).get("text", ""))
            body = {"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": "echo:" + text}],
                "isError": False}}
            payload = json.dumps(body)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.write(("event: message\\ndata: " + payload + "\\n\\n").encode())
        else:
            self._json(200, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601, "message": "method not found"}})


srv = HTTPServer(("127.0.0.1", 0), H)
print("READY %d" % srv.server_address[1], flush=True)
srv.serve_forever()
""";


"""Spawn the fake HTTP server on an ephemeral port; returns the process and
its URL (blocks until the server prints READY <port>)."""
def _start_fake_http_server(tmp: str) -> tuple[any, str] {
    path: str = os.path.join(tmp, "mcp_http_server.py");
    with open(path, "w") as f { f.write(FAKE_HTTP_SERVER_SRC); }
    err_path: str = os.path.join(tmp, "mcp_http_server.err");
    err_fh: any = open(err_path, "w");
    proc = subprocess.Popen(
        [sys.executable, path], stdout=subprocess.PIPE,
        stderr=err_fh, text=True, bufsize=1,
    );
    out_pipe: any = proc.stdout;
    ready: str = out_pipe.readline().strip();
    if not ready.startswith("READY ") {
        proc.terminate();
        try { proc.wait(timeout=5.0); } except Exception {
            proc.kill();
        }
        err_fh.close();
        err_txt: str = "";
        try {
            err_txt = open(err_path).read()[:500];
        } except Exception {
        }
        raise RuntimeError(
            "fake http server did not start: " + ready + " | stderr: " + err_txt
        );
    }
    err_fh.close();
    port: int = int(ready.split(" ")[1]);
    url: str = "http://127.0.0.1:" + str(port) + "/mcp";
    return (proc, url);
}


test "http transport round trip: initialize, session echo, json and sse bodies" {
    tmp = tempfile.mkdtemp();
    proc: any = None;
    client = create_mcp_client();
    try {
        started_up = _start_fake_http_server(tmp);
        proc = started_up[0];
        url: str = started_up[1];
        res = mcp_start_http(client, url, {"X-Probe": "on"}, timeout_s=10.0);
        assert res["ok"] is True, res;
        assert res.get("server_name") == "fake-http-mcp";
        # session id captured from the initialize response
        assert client.session_id == "sess-42";
        # tools/list over the JSON body path (session id must be echoed or
        # the server rejects with 400)
        listed = mcp_list_tools(client, timeout_s=10.0);
        assert listed["ok"] is True, listed;
        tools: any = listed.get("tools", []);
        assert len(tools) == 1;
        assert str(tools[0]["name"]) == "echo";
        # tools/call over the text/event-stream body path
        call = mcp_call_tool(client, "echo", {"text": "hi"}, timeout_s=10.0);
        assert call["ok"] is True, call;
        assert str(call.get("result", "")) == "echo:hi";
        # unknown method -> honest JSON-RPC error
        bad = mcp_call_tool(client, "nope", {}, timeout_s=10.0);
        assert bad["ok"] is False;
        assert "method not found" in str(bad.get("error", ""));
        # stop sends DELETE; a fresh initialize on the same client works
        assert mcp_stop(client)["ok"] is True;
        again = mcp_start_http(client, url, timeout_s=10.0);
        assert again["ok"] is True, again;
    } finally {
        mcp_stop(client);
        if proc is not None {
            proc.terminate();
            try { proc.wait(timeout=5.0); } except Exception {
                proc.kill();
            }
        }
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "http transport refuses bad urls and reports unreachable servers" {
    client = create_mcp_client();
    bad_scheme = mcp_start_http(client, "ftp://example.invalid/mcp");
    assert bad_scheme["ok"] is False;
    assert "http(s) url" in str(bad_scheme.get("error", ""));
    # port 9 on loopback: nothing listens -> connection refused, fast
    refused = mcp_start_http(client, "http://127.0.0.1:9/mcp", timeout_s=5.0);
    assert refused["ok"] is False;
    err: str = str(refused.get("error", ""));
    assert "initialize failed" in err, err;
}
