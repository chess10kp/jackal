import os;

def load_extension(
    bridge: PluginBridge,
    reg: ToolRegistry,
    extension_id: str,
    tool_defs: list[dict[str, any]],
    handlers: dict[str, any],
) -> list[str];
def caps_satisfied(bridge: PluginBridge, requires: list[str]) -> list[any];
def ui_cap_satisfied(bridge: PluginBridge, requires: list[str], has_ui: bool) -> bool;
def load_extension_path(
    bridge: PluginBridge,
    reg: ToolRegistry,
    extension_id: str,
    path: str,
    timeout: float = 5.0,
    requires: list[str] = [],
    has_ui: bool = False,
) -> list[str];

def unload_extension(bridge: PluginBridge, reg: ToolRegistry, extension_id: str) -> int;

def invoke_shortcut(bridge: PluginBridge, key: str, timeout: float = 10.0) -> dict[str, any];

def cancel_tool(bridge: PluginBridge, correlation_id: str);
def drain_inbox(bridge: PluginBridge) -> list[str];
def invoke_command(
    bridge: PluginBridge, name: str, args: str = "", timeout: float = 10.0
) -> dict[str, any];
