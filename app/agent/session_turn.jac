import sys;
import os;
import time;

def render_event(kind: str, data: dict[str, any]);

def relay_tool_hooks(bridge: PluginBridge | None, inner: any) -> any;
def _apply_extension_traffic(bridge: PluginBridge | None, on_event: any);
def compaction_cut(msgs: list[dict[str, any]], keep_tail: int, floor: int = 0) -> int;
def compact_history(bridge: PluginBridge | None = None, force: bool = False) -> dict[str, any];
def _maybe_auto_compact(bridge: PluginBridge | None);
def compact_now -> str;
def _ensure_mode_system_prompt;

def run_turn(
    message: str, on_event: any = render_event, approve: any = None, max_iters: int = 30
) -> str;
