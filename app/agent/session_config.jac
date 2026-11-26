import os;
import json;
import time;
import fnmatch;
import threading;

glob _MCP_REVIVE_LOCK: any = threading.Lock();

def set_mode(next_mode: str) -> str;
def get_mode -> str;

def _mcp_name_chunk(raw: any) -> str;
def _mcp_server_specs(cfg: dict[str, any]) -> dict[str, dict[str, any]];
def _make_mcp_handler(client: McpClient, server_name: str, tool_name: str) -> Callable[[
    dict[str, any],
], str];
def _make_mcp_resource_handler(client: McpClient, server_name: str) -> Callable[[
    dict[str, any],
], str];
def _register_resource_tool(reg: ToolRegistry, server_name: str, client: McpClient) -> int;
def mcp_server_specs(cfg: dict[str, any]) -> dict[str, list[str]];
def _user_config_path -> str;
def _load_json_dict(path: str) -> dict[str, any];
def mcp_config(cwd: str) -> dict[str, any];
def mcp_configured_specs -> dict[str, list[str]];
def _legacy_mcp_sources(agent_dir: str) -> list[str];
def mcp_import_legacy(home_dir: str = "", sources: list[str] = []) -> list[str];

def _mcp_set_status(
    server_name: str,
    state: str,
    error: str = "",
    tools: int = 0,
    cmd: list[str] | None = None,
    denied: int = 0,
);

def _mcp_fail(server_name: str, error: str);
def _revive_client(server_name: str) -> bool;
def mcp_health_check;
def drain_mcp_notices -> list[str];
def mcp_pump_notifications;
def _refresh_server_tools(server_name: str);
def _register_server_tools(
    reg: ToolRegistry, server_name: str, client: McpClient, spec: dict[str, any], tools: list[any]
) -> dict[str, any];
def _attach_one_mcp_server(server_name: str, spec_json: str);
def _attach_mcp_servers;
def mcp_restart(server_name: str) -> str;
def mcp_resources(server_name: str, uri: str) -> str;
def mcp_prompt(server_name: str, prompt_name: str, args_json: str) -> str;
def mcp_restart_failed -> str;
def wait_mcp_ready(timeout_s: float = -1.0) -> bool;
def mcp_status_lines -> list[str];

def _model_prefs_path -> str;
def _load_model_prefs;
def _record_model_pref(name: str);
def model_preferences -> dict[str, any];
def set_model(name: str) -> str;
def set_thinking_level(level: str) -> str;

def clear_history;
def _apply_pending_model_requests;
