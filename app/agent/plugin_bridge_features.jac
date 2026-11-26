import json;

def transform_markdown(
    bridge: PluginBridge | None,
    markdown: str,
    message_type: str = "assistant",
    streaming: bool = False,
) -> dict[str, any];
def drain_extension_traffic(bridge: PluginBridge | None) -> dict[str, any];
def set_session_name(bridge: PluginBridge, name: str, timeout: float = 5.0) -> bool;
def resolve_ext_model(bridge: PluginBridge | None, model_id: str) -> dict[str, any] | None;
def prepare_provider_request(
    bridge: PluginBridge | None, model: str, url: str, headers: dict[str, str], body: dict[str, any]
) -> dict[str, any];
def _fake_content_lines(out: any) -> list[str];
def render_extension_block(
    bridge: PluginBridge | None, kind: str, entry_type: str, payload: any
) -> dict[str, any];
