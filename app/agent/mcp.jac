import json;
import os;
import shutil;
import subprocess;
import sys;
import tempfile;
import threading;
import time;
import urllib.error;
import urllib.request;

glob DEFAULT_TIMEOUT_S: float = 15.0,
     MAX_NOTIFICATIONS: int = 1000,
     MAX_LIST_PAGES: int = 64;

glob MCP_PROTOCOL_VERSION: str = "2025-06-18";

obj McpClient {
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
        reader_thread: any = None,
        on_request: any = None,
        transport: str = "stdio",
        url: str = "",
        headers: dict[str, str] = {},
        session_id: str = "";

    def start(server_cmd: list[str], timeout_s: float = -1.0) -> dict[str, any];

    def list_tools(timeout_s: float = -1.0) -> dict[str, any];

    def call_tool(name: str, arguments: dict[str, any], timeout_s: float = -1.0) -> dict[str, any];

    def stop -> dict[str, any];
}

def create_mcp_client(timeout_s: float = DEFAULT_TIMEOUT_S) -> McpClient;

def _alive(client: McpClient) -> bool;

def _ensure_io(client: McpClient);
def _reader_loop(client: McpClient);
def _http_error_response(client: McpClient, he: any) -> dict[str, any];
def _http_exchange(
    client: McpClient, msg: dict[str, any], timeout_s: float, expect_body: bool
) -> any;

def _start_reader(client: McpClient);

def _stop_reader(client: McpClient);

def _write_line(client: McpClient, msg: dict[str, any]);
def _request(
    client: McpClient, method: str, params: dict[str, any], timeout_s: float
) -> dict[str, any];
def _response_payload(resp: dict[str, any]) -> dict[str, any];

def _effective_timeout(client: McpClient, timeout_s: float) -> float;
def mcp_start(
    client: McpClient,
    server_cmd: list[str],
    timeout_s: float = -1.0,
    env_extra: dict[str, str] | None = None,
    cwd: str = "",
) -> dict[str, any];
def mcp_start_http(
    client: McpClient, url: str, headers: dict[str, str] | None = None, timeout_s: float = -1.0
) -> dict[str, any];
def mcp_list_tools(client: McpClient, timeout_s: float = -1.0) -> dict[str, any];
def mcp_call_tool(
    client: McpClient, name: str, arguments: dict[str, any], timeout_s: float = -1.0
) -> dict[str, any];
def mcp_stop(client: McpClient) -> dict[str, any];
def mcp_tool_specs(
    client: McpClient, prefix: str = "", timeout_s: float = -1.0
) -> list[dict[str, any]];
def mcp_is_alive(client: McpClient) -> bool;
def mcp_drain_notifications(client: McpClient) -> list[dict[str, any]];
def mcp_list_prompts(client: McpClient, timeout_s: float = -1.0) -> dict[str, any];
def mcp_get_prompt(
    client: McpClient, name: str, arguments: dict[str, any], timeout_s: float = -1.0
) -> dict[str, any];
def mcp_list_resources(client: McpClient, timeout_s: float = -1.0) -> dict[str, any];
def mcp_read_resource(client: McpClient, uri: str, timeout_s: float = -1.0) -> dict[str, any];
def _serve_inbound(client: McpClient, rid: any, method: str, params: dict[str, any]);
def mcp_set_request_handler(client: McpClient, handler: any);
