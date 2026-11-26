import os;

obj SessionPlugins {
    has session_id: str = "session",
        cwd: str = "",
        bridge: PluginBridge | None = None,
        reg: any = None,
        decls: list[any] = [],
        loaded: int = 0,
        total: int = 0,
        ready: bool = True,
        phase: str = "idle",
        detail: str = "",
        t_interactive: float = 0.0,
        t_ext_ready: float = 0.0,
        prompt_queue: list[str] = [],
        warm_future: Task[None] | None = None,
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

glob history: list[dict[str, any]] = [],
     show_stats: bool = True,
     model: str = os.environ.get("JACKAL_MODEL", "openrouter/anthropic/claude-sonnet-5"),
     thinking_level: str = "",
     mode: str = "normal",
     plugins: SessionPlugins = SessionPlugins(),
     _t0: float = 0.0,
     _n_tools: int = 0,
     _model_prefs: dict[str, any] = {},
     _model_prefs_loaded: bool = False;

def set_mode_state(next_mode: str);

def get_mode_state -> str;

def set_model_state(name: str);

def get_model_state -> str;

def set_thinking_level_state(level: str);

def get_thinking_level_state -> str;

def reset_turn_stats(t0: float);

def bump_tool_count;
def adopt_model_prefs(raw: dict[str, any]);
