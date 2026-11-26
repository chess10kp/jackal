import json;

def _absorb_hook_results(bridge: PluginBridge, results: list[any]);
def fire_hook_data(
    bridge: PluginBridge | None, event: str, data: dict[str, any], timeout: float = 10.0
) -> dict[str, any];
def _ok_verdicts(results: list[any]) -> list[any];
def tool_call_gate(bridge: PluginBridge | None, name: str, args: dict[str, any]) -> dict[str, any];
def tool_result_gate(
    bridge: PluginBridge | None, name: str, args: dict[str, any], result: str
) -> dict[str, any];
def input_gate(bridge: PluginBridge | None, text: str) -> dict[str, any];
def context_gate(
    bridge: PluginBridge | None, messages: list[dict[str, any]]
) -> list[dict[str, any]];
def agent_start_gate(bridge: PluginBridge | None, prompt: str) -> dict[str, any];

def fire_hook(
    bridge: PluginBridge, event: str, data: dict[str, any], timeout: float = 10.0
) -> list[dict[str, any]];
def fire_user_bash(
    bridge: PluginBridge | None, command: str, result: str = ""
) -> list[dict[str, any]];
def fire_project_trust(bridge: PluginBridge | None, path: str) -> list[dict[str, any]];
