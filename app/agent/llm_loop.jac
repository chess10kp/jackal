import json;
import time;

obj TurnCancel {
    has turn_id: str = "",
        cancelled: bool = False,
        reason: str = "user";
}

def _tool_defs(specs: list[ToolSpec]) -> list[dict[str, any]];

def _find_spec(specs: list[ToolSpec], name: str) -> ToolSpec | None;

def _is_transient_error(message: str) -> bool;

def _cap_tool_result(result: any) -> str;
def _notify_message_end(bridge: any, message: dict[str, any]);
def react_loop(
    messages: list[dict[str, any]],
    specs: list[ToolSpec],
    transport: Transport,
    on_event: any,
    max_iters: int = 30,
    reg: ToolRegistry | None = None,
    bridge: any = None,
    max_retries: int = 2,
    cancel: TurnCancel | None = None,
    approve: any = None,
) -> str;
