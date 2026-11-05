"""Mutable plugin/session control-plane state.

Kept separate from scalar session state so model/mode accessors have a small
native module boundary independent of bridge and MCP object layouts.
"""

import from .mcp { McpClient }


obj:pub SessionPlugins {
    has session_id: str = "session",
        cwd: str = "",
        bridge: any = None,
        reg: int = 0,
        decls: list[any] = [],
        loaded: int = 0,
        total: int = 0,
        ready: bool = True,
        phase: str = "idle",
        detail: str = "",
        t_interactive: float = 0.0,
        t_ext_ready: float = 0.0,
        prompt_queue: list[str] = [],
        warm_future: any = None,
        wait_budget_s: float = 5.0,
        commands: dict[str, any] = {},
        interactive_ui: bool = False,
        active_cancel: any = None,
        mcp_clients: dict[str, McpClient] = {},
        mcp_specs: dict[str, dict[str, any]] = {},
        mcp_read_only: dict[str, list[str]] = {},
        mcp_owned: dict[str, str] = {},
        mcp_tools: int = 0,
        mcp_status: dict[str, dict[str, any]] = {},
        mcp_notices: list[str] = [];
}


glob:pub plugins: SessionPlugins = SessionPlugins();


"""Return the active bridge as a boxed Jac value across module boundaries."""
def:pub get_plugin_bridge() -> any {
    return plugins.bridge;
}
