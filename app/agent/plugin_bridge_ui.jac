import time;

def poll_ui_request(bridge: PluginBridge) -> dict[str, any] | None;
def respond_ui(bridge: PluginBridge, corr: str, value: any) -> bool;
def cancel_ui(bridge: PluginBridge, corr: str, reason: str = "cancelled") -> bool;
def cancel_all_ui(bridge: PluginBridge, reason: str = "cancelled") -> int;
