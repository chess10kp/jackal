"""MCP config breadth tests — spec parsing (env/cwd/enabled/timeout) and
the user-level + project-level merge.

Same-stem annex of session_config.jac (merged automatically): local names
are used directly, no import from .session_config.
"""

import os;
import sys;
import json;
import tempfile;
import shutil;


def _write_project_cfg(base: str, cfg: dict[str, any]) {
    os.makedirs(os.path.join(base, ".jackal", "sessions"), exist_ok=True);
    fh: any = open(os.path.join(base, ".jackal", "config.json"), "w");
    fh.write(json.dumps(cfg));
    fh.close();
}


test "mcp server specs parse env, cwd, enabled, and timeout" {
    cfg = {"mcp": {"servers": {
        "full": {
            "command": "uvx",
            "args": ["some-server"],
            "env": {"TOKEN": "abc", "N": 3},
            "cwd": "/tmp/srv",
            "timeout": 30,
        },
        "off": {"command": "true", "enabled": False},
        "minimal": {"command": ["jac", "mcp"]},
        "bad": {"args": ["no-command"]},
    }}};
    specs = _mcp_server_specs(cfg);
    names = sorted(list(specs.keys()));
    assert names == ["full", "minimal", "off"];
    full: any = specs["full"];
    assert full["cmd"] == ["uvx", "some-server"];
    assert full["env"] == {"TOKEN": "abc", "N": "3"};
    assert full["cwd"] == "/tmp/srv";
    assert full["enabled"] is True;
    assert full["timeout"] == 30.0;
    assert specs["off"]["enabled"] is False;
    minimal: any = specs["minimal"];
    assert minimal["cmd"] == ["jac", "mcp"];
    assert minimal["env"] == {};
    assert minimal["cwd"] == "";
    assert minimal["enabled"] is True;
    assert minimal["timeout"] == -1.0;
    # public alias keeps the {name: argv} shape the status window renders
    argv = mcp_server_specs(cfg);
    assert argv["full"] == ["uvx", "some-server"];
    assert "off" in argv;
}


test "user-level config merges beneath the project config" {
    tmp_dir = tempfile.mkdtemp(prefix="jackal-mcp-cfg-");
    agent_dir = os.path.join(tmp_dir, "agentdir");
    os.makedirs(agent_dir);
    old_env = os.environ.get("JACKAL_AGENT_DIR", "");
    os.environ["JACKAL_AGENT_DIR"] = agent_dir;
    try {
        # User level: a user-only server and a shared server (user flavor).
        fh: any = open(os.path.join(agent_dir, "config.json"), "w");
        fh.write(json.dumps({"mcp": {"servers": {
            "useronly": {"command": "user-cmd"},
            "shared": {"command": "user-shared", "env": {"U": "1"}},
        }}}));
        fh.close();
        # Project level: shared overrides wholesale; project-only added.
        proj = os.path.join(tmp_dir, "proj");
        _write_project_cfg(proj, {"mcp": {"servers": {
            "shared": {"command": "proj-shared", "cwd": "/w"},
            "projonly": {"command": "proj-cmd"},
        }}});
        eff = mcp_config(proj);
        servers: any = eff["mcp"]["servers"];
        snames = sorted(list(servers.keys()));
        assert snames == ["projonly", "shared", "useronly"];
        # project entry replaces the user entry wholesale (same name wins)
        assert servers["shared"]["command"] == "proj-shared";
        assert servers["shared"].get("cwd") == "/w";
        assert servers["useronly"]["command"] == "user-cmd";
        assert servers["projonly"]["command"] == "proj-cmd";
        # and the parsed specs reflect the merge
        specs = _mcp_server_specs(eff);
        assert specs["shared"]["cwd"] == "/w";
        assert "useronly" in specs;
        assert "projonly" in specs;
    } finally {
        if old_env {
            os.environ["JACKAL_AGENT_DIR"] = old_env;
        } else {
            os.environ.pop("JACKAL_AGENT_DIR", None);
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}


test "missing user config yields project-only mcp config" {
    tmp_dir = tempfile.mkdtemp(prefix="jackal-mcp-cfg-");
    agent_dir = os.path.join(tmp_dir, "empty-agent");
    os.makedirs(agent_dir);
    old_env = os.environ.get("JACKAL_AGENT_DIR", "");
    os.environ["JACKAL_AGENT_DIR"] = agent_dir;
    try {
        proj = os.path.join(tmp_dir, "proj");
        _write_project_cfg(proj, {"mcp": {"servers": {
            "p": {"command": "pcmd"},
        }}});
        eff = mcp_config(proj);
        servers: any = eff["mcp"]["servers"];
        assert sorted(list(servers.keys())) == ["p"];
    } finally {
        if old_env {
            os.environ["JACKAL_AGENT_DIR"] = old_env;
        } else {
            os.environ.pop("JACKAL_AGENT_DIR", None);
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

glob REF_SERVER_SRC: str = """
import sys, json

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\\n")
    sys.stdout.flush()

calls = 0
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
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "ref-mcp", "version": "0"}}})
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        # Registration in the annex test is manual (the tool dict is passed
        # straight to _register_server_tools), so the FIRST list request
        # already belongs to the post-change refresh.
        calls += 1
        name = "alpha" if calls == 0 else "beta"
        send({"jsonrpc": "2.0", "id": rid, "result": {"tools": [
            {"name": name, "description": "refcount tool",
             "inputSchema": {"type": "object", "properties": {},
                             "required": []}}]}})
    elif rid is not None:
        send({"jsonrpc": "2.0", "id": rid, "error": {
            "code": -32601, "message": "method not found"}})
""";


def _reset_mcp_plugin_state {
    plugins.mcp_clients.clear();
    plugins.mcp_status.clear();
    plugins.mcp_specs.clear();
    plugins.mcp_read_only.clear();
    plugins.mcp_owned.clear();
    plugins.mcp_notices.clear();
    plugins.mcp_tools = 0;
    plugins.reg = None;
}


def _spec_for(cmd: list[str]) -> dict[str, any] {
    return {
        "cmd": cmd,
        "env": {},
        "cwd": "",
        "enabled": True,
        "timeout": -1.0,
        "read_only": False,
        "read_only_tools": [],
    };
}


test "tools/list_changed refresh diffs the registry without a respawn" {
    tmp = tempfile.mkdtemp(prefix="jackal-mcp-ref-");
    reg = ToolRegistry();
    plugins.reg = reg;
    client = create_mcp_client();
    try {
        path = os.path.join(tmp, "ref_server.py");
        fh: any = open(path, "w");
        fh.write(REF_SERVER_SRC);
        fh.close();
        cmd = [sys.executable, path];
        started = mcp_start(client, cmd, timeout_s=10.0);
        assert started.get("ok") is True, str(started.get("error", "no error"));
        plugins.mcp_clients["t"] = client;
        plugins.mcp_specs["t"] = _spec_for(cmd);
        plugins.mcp_status["t"] = {"state": "connected", "error": "", "tools": 0, "cmd": cmd};
        stats = _register_server_tools(reg, "t", client, plugins.mcp_specs["t"], [
            {"name": "alpha", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(stats["registered"]) == 1;
        assert get_tool(reg, "mcp_t_alpha") is not None;
        assert plugins.mcp_owned.get("mcp_t_alpha", "") == "t";

        # Server now serves "beta"; a buffered list_changed must diff.
        client.notifications.append({
            "jsonrpc": "2.0", "method": "notifications/tools/list_changed",
        });
        mcp_pump_notifications();
        reg_names = sorted([str(k) for k in reg.tools.keys()]);
        notes = " | ".join(plugins.mcp_notices);
        assert get_tool(reg, "mcp_t_alpha") is None, (
            "alpha still registered: " + str(reg_names) + " notices: " + notes);
        assert get_tool(reg, "mcp_t_beta") is not None, (
            "beta missing: " + str(reg_names) + " notices: " + notes);
        assert plugins.mcp_owned.get("mcp_t_beta", "") == "t";
        assert int(plugins.mcp_status["t"]["tools"]) == 1;
        joined = " ".join(plugins.mcp_notices);
        assert "tool list changed" in joined;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
        _reset_mcp_plugin_state();
    }
}


test "cross-server tool name collisions rename deterministically" {
    reg = ToolRegistry();
    plugins.reg = reg;
    dummy = create_mcp_client();
    try {
        spec = _spec_for(["noop"]);
        s1 = _register_server_tools(reg, "a.b", dummy, spec, [
            {"name": "x", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s1["registered"]) == 1 and int(s1["lost"]) == 0;
        assert get_tool(reg, "mcp_a_b_x") is not None;
        # "a-b" sanitizes to the same chunk: second registration must rename
        s2 = _register_server_tools(reg, "a-b", dummy, spec, [
            {"name": "x", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s2["registered"]) == 1 and int(s2["lost"]) == 0;
        assert get_tool(reg, "mcp_a_b_x_2") is not None;
        assert plugins.mcp_owned.get("mcp_a_b_x", "") == "a.b";
        assert plugins.mcp_owned.get("mcp_a_b_x_2", "") == "a-b";
        joined = " ".join(plugins.mcp_notices);
        assert "collision" in joined;
        # same-server re-registration replaces silently (no _3)
        s3 = _register_server_tools(reg, "a-b", dummy, spec, [
            {"name": "x", "description": "d2", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s3["registered"]) == 1;
        assert get_tool(reg, "mcp_a_b_x_2") is not None;
        assert get_tool(reg, "mcp_a_b_x_3") is None;
    } finally {
        _reset_mcp_plugin_state();
    }
}
