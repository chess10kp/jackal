obj Envelope {
    has version: int = 1,
        session_id: str = "",
        request_id: str = "",
        turn_id: str = "",
        tool_id: str = "",
        sequence: int = 0,
        correlation_id: str = "",
        kind: str = "",
        payload: dict[str, any] = {};
}

obj QueueStats {
    has depth: int = 0,
        dropped: int = 0,
        coalesced: int = 0;
}

obj BoundedEventQueue {
    has capacity: int = 256,
        items: list[Envelope] = [],
        dropped: int = 0,
        coalesced: int = 0;
}

obj CancelToken {
    has turn_id: str = "",
        group_id: str = "",
        cancelled: bool = False;
}

obj InProcessAdapter {
    has queue: BoundedEventQueue,
        session_id: str = "",
        last_sequence: int = 0,
        cancelled_turns: set[str] = set(),
        cancelled_groups: set[str] = set(),
        stream_buf: str = "",
        last_tool: str = "",
        pending_approval_id: str = "",
        busy: bool = False;
}

def create_queue(capacity: int = 256) -> BoundedEventQueue;

def create_adapter(session_id: str, capacity: int = 256) -> InProcessAdapter;

def make_envelope(
    kind: str,
    payload: dict[str, any] | None = None,
    session_id: str = "",
    request_id: str = "",
    turn_id: str = "",
    tool_id: str = "",
    sequence: int = 0,
    correlation_id: str = "",
    version: int = 1,
) -> Envelope;

def queue_stats(queue: BoundedEventQueue) -> QueueStats;
def can_coalesce(a: Envelope, b: Envelope) -> bool;
def coalesce_text_deltas(a: Envelope, b: Envelope) -> Envelope;
def enqueue(queue: BoundedEventQueue, envelope: Envelope) -> bool;
def dequeue(queue: BoundedEventQueue) -> Envelope | None;
def cancel_turn(adapter: InProcessAdapter, turn_id: str) -> CancelToken;
def cancel_group(adapter: InProcessAdapter, group_id: str) -> CancelToken;
def drive_screen(adapter: InProcessAdapter, shell: any, envelope: Envelope);
def drain_and_drive(adapter: InProcessAdapter, shell: any) -> int;

glob UI_KINDS: set[str] = {
    "turn_start",
    "text_delta",
    "status",
    "insert_text",
    "tool_start",
    "tool_end",
    "approval_request",
    "approval_decision",
    "turn_cancelled",
    "group_cancelled",
    "turn_end",
};

glob PLUGIN_KINDS: set[str] = {
    "host_hello",
    "host_goodbye",
    "host_status",
    "ext_load",
    "ext_unload",
    "ext_loaded",
    "tool_invoke",
    "tool_result",
    "tool_cancel",
    "tool_update",
    "cmd_invoke",
    "cmd_result",
    "shortcut_invoke",
    "shortcut_result",
    "hook_fire",
    "hook_done",
    "md_transform",
    "md_transformed",
    "render_message",
    "rendered",
    "ui_request",
    "ui_response",
    "ui_cancel",
};

def is_ui_kind(kind: str) -> bool;

def is_plugin_kind(kind: str) -> bool;
def make_plugin_envelope(
    kind: str,
    payload: dict[str, any] | None = None,
    session_id: str = "",
    correlation_id: str = "",
    tool_id: str = "",
    turn_id: str = "",
    sequence: int = 0,
) -> Envelope;
