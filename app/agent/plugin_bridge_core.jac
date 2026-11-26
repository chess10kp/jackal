import json;

obj PluginBridge {
    has session_id: str = "",
        host: FakePluginHost | None = None,
        host_kind: str = "",
        proc: any = None,
        node_bin: str = "node",
        host_mjs: str = "",
        next_corr: int = 1,
        inbox: list[Envelope] = [],
        last_active: float = 0.0,
        status_phase: str = "idle",
        idle_timeout_s: float = 300.0,
        pending: dict[str, any] = {},
        reply_q: any = None,
        reader_stop: any = None,
        reader_thread: any = None,
        write_lock: any = None,
        restart_used: bool = False,
        host_caps: list[str] = [],
        compat_tier: str = "T0",
        hello_payload: dict[str, any] = {},
        commands: dict[str, any] = {},
        md_transformers: list[dict[str, any]] = [],
        providers: dict[str, any] = {},
        ui_q: any = None,
        interactive_ui: bool = False,
        traffic_messages: list[dict[str, any]] = [],
        traffic_entries: list[dict[str, any]] = [],
        session_name: str = "",
        shortcuts: dict[str, any] = {},
        labels: dict[str, any] = {},
        pending_model: str = "",
        pending_thinking_level: str = "";
    def invoke_js_tool(name: str, args: dict[str, any]) -> str;
}

def create_bridge(session_id: str) -> PluginBridge;

def _alloc_corr(bridge: PluginBridge) -> str;

def _node_alive(bridge: PluginBridge) -> bool;
def _emit_host_status(bridge: PluginBridge, phase: str, detail: str = "");
def invoke_tool(bridge: PluginBridge, name: str, args: dict[str, any]) -> str;

def _invoke_tool_fake(bridge: PluginBridge, name: str, args: dict[str, any]) -> str;

def _invoke_tool_node(bridge: PluginBridge, name: str, args: dict[str, any]) -> str;
