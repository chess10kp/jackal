"""Tests for agent/mcp.jac (same-stem annex, merged with the base module
at test time - no import of the own stem). Transport tests use the Node
newline-delimited JSON-RPC fixture in `mcp_test_server.mjs`; the real
`jac mcp` is never spawned here.

Fake server modes:
  normal   - handshake + echo/boom tools (transport basics)
  silent   - never answers tools/list (timeout path)
  paged    - tools/list pages 5 tools two at a time via nextCursor
  requests - sends sampling/roots server->client requests before tools/list;
             the listed tool name proves whether the client answered them
  dieafter - exits immediately after the initialized notification (EOF path)

A second mode in that fixture is a streamable-HTTP MCP server:
initialize issues Mcp-Session-Id sess-42 and post-initialize requests
without that header are rejected, tools/list answers as JSON, tools/call
answers as text/event-stream (both client response paths).
"""

def _write_mode_server(tmp: str, mode: str) -> list[str] {
    fixture: str = os.path.abspath(os.path.join(os.getcwd(), "agent", "mcp_test_server.mjs"));
    node_bin: str = os.environ.get("JACKAL_NODE_BIN", "node");
    return [node_bin, fixture, mode];
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


"""Spawn the Node fake HTTP server on an ephemeral port and read its READY line."""
def _start_fake_http_server(tmp: str) -> tuple[any, str] {
    fixture: str = os.path.abspath(os.path.join(os.getcwd(), "agent", "mcp_test_server.mjs"));
    node_bin: str = os.environ.get("JACKAL_NODE_BIN", "node");
    err_path: str = os.path.join(tmp, "mcp_http_server.err");
    err_fh: any = open(err_path, "w");
    proc = subprocess.Popen(
        [node_bin, fixture, "http"], stdout=subprocess.PIPE,
        stderr=err_fh, text=True,
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
