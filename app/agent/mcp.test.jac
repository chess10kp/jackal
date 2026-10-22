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
"""

glob FAKE_SERVER_SRC: str = """
import sys, json, time, os, select

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\\n")
    sys.stdout.flush()

mode = sys.argv[1] if len(sys.argv) > 1 else "normal"

def read_replies(want_ids, deadline):
    got = {}
    while len(got) < len(want_ids) and time.time() < deadline:
        remaining = deadline - time.time()
        if remaining <= 0:
            break
        ready, _, _ = select.select([sys.stdin], [], [], remaining)
        if not ready:
            break
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
            ]}})
    elif method == "tools/call":
        name = str(req.get("params", {}).get("name", ""))
        args = req.get("params", {}).get("arguments", {}) or {}
        if name == "echo":
            text = str(args.get("text", ""))
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": "echo:" + text}],
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
        assert len(specs) == 2;
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
