"""MCP config breadth tests — spec parsing (env/cwd/enabled/timeout) and
the user-level + project-level merge.

Same-stem annex of session_config.jac (merged automatically): local names
are used directly, no import from .session_config.
"""

import os;
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
