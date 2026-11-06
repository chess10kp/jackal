"""MCP config breadth tests — spec parsing (env/cwd/enabled/timeout) and
the user-level + project-level merge.

Same-stem annex of session_config.jac (merged automatically): local names
are used directly, no import from .session_config.
"""

import os;
import json;
import subprocess;
import tempfile;
import shutil;


def _write_project_cfg(base: str, cfg_json: str) {
    os.makedirs(os.path.join(base, ".jackal", "sessions"), exist_ok=True);
    fh = open(os.path.join(base, ".jackal", "config.json"), "w");
    fh.write(cfg_json);
    fh.close();
}


test "mcp server specs parse env, cwd, enabled, and timeout" {
    cfg: dict[str, any] = json.loads(
        "{\"mcp\":{\"servers\":{"
        + "\"full\":{\"command\":\"uvx\",\"args\":[\"some-server\"],"
        + "\"env\":{\"TOKEN\":\"abc\",\"N\":3},\"cwd\":\"/tmp/srv\",\"timeout\":30},"
        + "\"off\":{\"command\":\"true\",\"enabled\":false},"
        + "\"minimal\":{\"command\":[\"jac\",\"mcp\"]},"
        + "\"bad\":{\"args\":[\"no-command\"]}}}}"
    ) as dict[str, any];
    specs = _mcp_server_specs(cfg);
    names = sorted(list(specs.keys()));
    assert names == ["full", "minimal", "off"];
    full: dict[str, any] = specs["full"];
    assert full["cmd"] == ["uvx", "some-server"];
    assert full["env"] == {"TOKEN": "abc", "N": "3"};
    assert full["cwd"] == "/tmp/srv";
    assert full["enabled"] is True;
    assert full["timeout"] == 30.0;
    assert specs["off"]["enabled"] is False;
    minimal: dict[str, any] = specs["minimal"];
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
        fh = open(os.path.join(agent_dir, "config.json"), "w");
        fh.write(
            "{\"mcp\":{\"servers\":{\"useronly\":{\"command\":\"user-cmd\"},"
            + "\"shared\":{\"command\":\"user-shared\",\"env\":{\"U\":\"1\"}}}}}"
        );
        fh.close();
        # Project level: shared overrides wholesale; project-only added.
        proj = os.path.join(tmp_dir, "proj");
        _write_project_cfg(
            proj,
            "{\"mcp\":{\"servers\":{\"shared\":{\"command\":\"proj-shared\","
            + "\"cwd\":\"/w\"},\"projonly\":{\"command\":\"proj-cmd\"}}}}",
        );
        eff = mcp_config(proj);
        servers: dict[str, any] = eff["mcp"]["servers"] as dict[str, any];
        snames = sorted(list(servers.keys()));
        assert snames == ["projonly", "shared", "useronly"];
        # project entry replaces the user entry wholesale (same name wins)
        shared_server: dict[str, any] = servers["shared"] as dict[str, any];
        assert shared_server["command"] == "proj-shared";
        assert shared_server["cwd"] == "/w";
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
        _write_project_cfg(proj, "{\"mcp\":{\"servers\":{\"p\":{\"command\":\"pcmd\"}}}}");
        eff = mcp_config(proj);
        servers: dict[str, any] = eff["mcp"]["servers"] as dict[str, any];
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



def _reset_mcp_plugin_state {
    plugins.mcp_clients.clear();
    plugins.mcp_status.clear();
    plugins.mcp_specs.clear();
    plugins.mcp_read_only.clear();
    plugins.mcp_owned.clear();
    plugins.mcp_notices.clear();
    plugins.mcp_tools = 0;
    plugins.reg = 0;
}


def _refresh_server_cmd() -> list[str] {
    fixture: str = os.path.abspath(os.path.join(os.getcwd(), "agent", "mcp_test_server.mjs"));
    node_bin: str = os.environ.get("JACKAL_NODE_BIN", "node");
    return [node_bin, fixture, "refresh"];
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
    reg: int = create_registry_handle();
    plugins.reg = reg;
    client = create_mcp_client();
    try {
        cmd = _refresh_server_cmd();
        started = mcp_start(client, cmd, timeout_s=10.0);
        assert bool(started.get("ok")), str(started.get("error", "no error"));
        plugins.mcp_clients["t"] = client;
        plugins.mcp_specs["t"] = _spec_for(cmd);
        plugins.mcp_status["t"] = {"state": "connected", "error": "", "tools": 0, "cmd": cmd};
        stats = _register_server_tools(reg, "t", client, plugins.mcp_specs["t"], [
            {"name": "alpha", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(stats["registered"]) == 1;
        assert has_tool_handle(reg, "mcp_t_alpha");
        assert plugins.mcp_owned.get("mcp_t_alpha", "") == "t";

        # Server now serves "beta"; a buffered list_changed must diff.
        client.notifications.append({
            "jsonrpc": "2.0", "method": "notifications/tools/list_changed",
        });
        mcp_pump_notifications();
        reg_names: list[str] = registry_tool_names_handle(reg);
        reg_names.sort();
        notes = " | ".join(plugins.mcp_notices);
        assert not has_tool_handle(reg, "mcp_t_alpha"), (
            "alpha still registered: " + str(reg_names) + " notices: " + notes);
        assert has_tool_handle(reg, "mcp_t_beta"), (
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
    reg: int = create_registry_handle();
    plugins.reg = reg;
    dummy = create_mcp_client();
    try {
        spec = _spec_for(["noop"]);
        s1 = _register_server_tools(reg, "a.b", dummy, spec, [
            {"name": "x", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s1["registered"]) == 1 and int(s1["lost"]) == 0;
        assert has_tool_handle(reg, "mcp_a_b_x");
        # "a-b" sanitizes to the same chunk: second registration must rename
        s2 = _register_server_tools(reg, "a-b", dummy, spec, [
            {"name": "x", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s2["registered"]) == 1 and int(s2["lost"]) == 0;
        assert has_tool_handle(reg, "mcp_a_b_x_2");
        assert plugins.mcp_owned.get("mcp_a_b_x", "") == "a.b";
        assert plugins.mcp_owned.get("mcp_a_b_x_2", "") == "a-b";
        joined = " ".join(plugins.mcp_notices);
        assert "collision" in joined;
        # same-server re-registration replaces silently (no _3)
        s3 = _register_server_tools(reg, "a-b", dummy, spec, [
            {"name": "x", "description": "d2", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ]);
        assert int(s3["registered"]) == 1;
        assert has_tool_handle(reg, "mcp_a_b_x_2");
        assert not has_tool_handle(reg, "mcp_a_b_x_3");
    } finally {
        _reset_mcp_plugin_state();
    }
}

test "health check flips dead servers to failed with a notice" {
    tmp = tempfile.mkdtemp(prefix="jackal-mcp-hc-");
    reg: int = create_registry_handle();
    plugins.reg = reg;
    client = create_mcp_client();
    try {
        cmd = _refresh_server_cmd();
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        plugins.mcp_clients["t"] = client;
        plugins.mcp_specs["t"] = _spec_for(cmd);
        plugins.mcp_status["t"] = {"state": "connected", "error": "", "tools": 1, "cmd": cmd};
        # Kill the process out from under the healthy status.
        proc: subprocess.Popen = client.proc as subprocess.Popen;
        proc.kill();
        proc.wait(timeout=5);
        mcp_health_check();
        assert str(plugins.mcp_status["t"]["state"]) == "failed";
        assert "died" in str(plugins.mcp_status["t"]["error"]);
        joined = " ".join(plugins.mcp_notices);
        assert "unavailable" in joined;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
        _reset_mcp_plugin_state();
    }
}


test "a tool call against a dead server revives once and succeeds" {
    tmp = tempfile.mkdtemp(prefix="jackal-mcp-rv-");
    reg: int = create_registry_handle();
    plugins.reg = reg;
    client = create_mcp_client();
    try {
        cmd = _refresh_server_cmd();
        assert mcp_start(client, cmd, timeout_s=10.0)["ok"] is True;
        plugins.mcp_clients["t"] = client;
        plugins.mcp_specs["t"] = _spec_for(cmd);
        plugins.mcp_status["t"] = {"state": "connected", "error": "", "tools": 1, "cmd": cmd};
        handler = _make_mcp_handler(client, "t", "ping");
        # Kill the server, then call: transparent restart + retry must land.
        proc: subprocess.Popen = client.proc as subprocess.Popen;
        proc.kill();
        proc.wait(timeout=5);
        res: str = handler({});
        assert res == "pong", res;
        assert str(plugins.mcp_status["t"]["state"]) == "connected";
        joined = " ".join(plugins.mcp_notices);
        assert "restarted after unexpected death" in joined;
        # A healthy client is reused, not restarted again.
        notices_before = len(plugins.mcp_notices);
        assert handler({}) == "pong";
        assert len(plugins.mcp_notices) == notices_before;
    } finally {
        mcp_stop(client);
        shutil.rmtree(tmp, ignore_errors=True);
        _reset_mcp_plugin_state();
    }
}

test "allow_tools and deny_tools gate registration (deny wins)" {
    reg: int = create_registry_handle();
    plugins.reg = reg;
    dummy = create_mcp_client();
    try {
        spec = _spec_for(["noop"]);
        spec["allow_tools"] = ["read_*"];
        spec["deny_tools"] = ["read_secret*"];
        tools = [
            {"name": "read_docs", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
            {"name": "read_secret", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
            {"name": "write_docs", "description": "d", "inputSchema": {"type": "object", "properties": {}, "required": []}},
        ];
        stats = _register_server_tools(reg, "g", dummy, spec, tools);
        assert int(stats["registered"]) == 1;
        assert has_tool_handle(reg, "mcp_g_read_docs");
        assert not has_tool_handle(reg, "mcp_g_read_secret");
        assert not has_tool_handle(reg, "mcp_g_write_docs");
        assert int(stats["denied"]) == 2;
        denied_names: list[str] = stats["denied_names"] as list[str];
        denied_names_sorted: list[str] = [];
        for denied_name in denied_names { denied_names_sorted.append(str(denied_name)); }
        assert sorted(denied_names_sorted) == ["read_secret", "write_docs"];
    } finally {
        _reset_mcp_plugin_state();
    }
}

test "mcp_restart_failed restarts only failed servers" {
    reg: int = create_registry_handle();
    plugins.reg = reg;
    try {
        plugins.mcp_status = {
            "dead": {"state": "failed", "error": "boom", "tools": 0, "cmd": ["true"]},
            "alive": {"state": "connected", "error": "", "tools": 1, "cmd": ["true"]},
        };
        # Give the failed server a resolvable spec so restart can proceed.
        plugins.mcp_specs["dead"] = _spec_for(["true"]);
        out: str = mcp_restart_failed();
        assert out.startswith("restarting mcp servers: dead"), out;
        # The alive server is untouched (still its old status object state).
        assert str(plugins.mcp_status["alive"]["state"]) == "connected";
        # (The failed server's re-attach runs in a background flow; its state
        # moves connecting -> connected/failed on its own schedule.)
        # Nothing failed now -> honest no-op.
        plugins.mcp_status["dead"]["state"] = "connected";
        assert mcp_restart_failed() == "no failed mcp servers";
    } finally {
        _reset_mcp_plugin_state();
    }
}


test "legacy mcp.json import is one-time, shape-mapped, and collision-safe" {
    tmp = tempfile.mkdtemp(prefix="jackal-mcp-import-");
    old_agent_dir = os.environ.get("JACKAL_AGENT_DIR", "");
    old_no_import = os.environ.get("JACKAL_MCP_NO_IMPORT", "");
    try {
        home_dir = os.path.join(tmp, "home");
        os.makedirs(home_dir);
        # hermetic: agent dir without config.json, import not disabled
        agent_dir: str = os.path.join(tmp, "agent");
        os.environ["JACKAL_AGENT_DIR"] = agent_dir;
        os.makedirs(agent_dir, exist_ok=True);
        os.environ.pop("JACKAL_MCP_NO_IMPORT", None);
        src1 = os.path.join(tmp, "cursor.json");
        with open(src1, "w") as f {
            f.write(
                "{\"mcpServers\":{\"leg_one\":{\"command\":\"uvx\",\"args\":[\"srv-one\"]},"
                + "\"leg_off\":{\"command\":[\"jac\",\"mcp\"],\"disabled\":true},"
                + "\"leg_web\":{\"url\":\"https://x.example/mcp\"},"
                + "\"leg_bare\":{\"args\":[\"no-command\"]}}}"
            );
        }
        src2 = os.path.join(tmp, "vscode.json");
        with open(src2, "w") as f {
            f.write(
                "{\"mcpServers\":{\"leg_one\":{\"command\":\"other\"},"
                + "\"leg_two\":{\"command\":\"npx\",\"args\":[\"srv-two\"],"
                + "\"env\":{\"K\":\"V\"}}}}"
            );
        }
        imported = mcp_import_legacy(
            home_dir=home_dir, sources=[src1, src2],
        );
        assert sorted(imported) == ["leg_off", "leg_one", "leg_two"], imported;
        # user config written with mapped entries
        user_cfg: dict[str, any] = json.load(open(os.path.join(home_dir, ".jackal", "config.json"))) as dict[str, any];
        servers: dict[str, any] = user_cfg["mcp"]["servers"] as dict[str, any];
        assert servers["leg_one"]["command"] == "uvx";
        assert servers["leg_one"]["args"] == ["srv-one"];
        assert servers["leg_off"]["enabled"] is False;
        assert servers["leg_two"]["env"] == {"K": "V"};
        # http-shaped and malformed entries never import
        assert "leg_web" not in servers;
        assert "leg_bare" not in servers;
        # one-time marker: a second call is a no-op
        again = mcp_import_legacy(home_dir=home_dir, sources=[src1, src2]);
        assert again == [];
        user_cfg2: dict[str, any] = json.load(open(os.path.join(home_dir, ".jackal", "config.json"))) as dict[str, any];
        servers2: dict[str, any] = user_cfg2["mcp"]["servers"] as dict[str, any];
        assert "leg_web" not in servers2;
    } finally {
        if old_agent_dir {
            os.environ["JACKAL_AGENT_DIR"] = old_agent_dir;
        } else {
            os.environ.pop("JACKAL_AGENT_DIR", None);
        }
        if old_no_import {
            os.environ["JACKAL_MCP_NO_IMPORT"] = old_no_import;
        } else {
            os.environ.pop("JACKAL_MCP_NO_IMPORT", None);
        }
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "legacy import respects JACKAL_MCP_NO_IMPORT and existing names" {
    tmp = tempfile.mkdtemp(prefix="jackal-mcp-import2-");
    old_agent_dir = os.environ.get("JACKAL_AGENT_DIR", "");
    old_no_import = os.environ.get("JACKAL_MCP_NO_IMPORT", "");
    try {
        home_dir = os.path.join(tmp, "home");
        os.makedirs(home_dir);
        agent_dir: str = os.path.join(tmp, "agent");
        os.environ["JACKAL_AGENT_DIR"] = agent_dir;
        os.makedirs(agent_dir, exist_ok=True);
        os.environ.pop("JACKAL_MCP_NO_IMPORT", None);
        # pre-existing user config: its names are not re-imported/overwritten
        target = os.path.join(home_dir, ".jackal", "config.json");
        os.makedirs(os.path.dirname(target), exist_ok=True);
        with open(target, "w") as f {
            f.write("{\"mcp\":{\"servers\":{\"leg_one\":{\"command\":\"already-here\"}}}}");
        }
        src1 = os.path.join(tmp, "cursor.json");
        with open(src1, "w") as f {
            f.write("{\"mcpServers\":{\"leg_one\":{\"command\":\"uvx\"},\"leg_two\":{\"command\":\"npx\"}}}");
        }
        imported = mcp_import_legacy(home_dir=home_dir, sources=[src1]);
        assert imported == ["leg_two"], imported;
        user_cfg: any = json.load(open(target));
        assert user_cfg["mcp"]["servers"]["leg_one"]["command"] == "already-here";
        # opt-out env var: nothing imports, no marker written
        home2 = os.path.join(tmp, "home2");
        os.makedirs(home2);
        os.environ["JACKAL_MCP_NO_IMPORT"] = "1";
        skipped = mcp_import_legacy(home_dir=home2, sources=[src1]);
        assert skipped == [];
        assert not os.path.isfile(os.path.join(home2, ".jackal", "mcp_import_done"));
    } finally {
        if old_agent_dir {
            os.environ["JACKAL_AGENT_DIR"] = old_agent_dir;
        } else {
            os.environ.pop("JACKAL_AGENT_DIR", None);
        }
        if old_no_import {
            os.environ["JACKAL_MCP_NO_IMPORT"] = old_no_import;
        } else {
            os.environ.pop("JACKAL_MCP_NO_IMPORT", None);
        }
        shutil.rmtree(tmp, ignore_errors=True);
    }
}
