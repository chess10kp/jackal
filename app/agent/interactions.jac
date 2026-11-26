import threading;

obj UiInteraction {
    has corr: str = "",
        parent_corr: str = "",
        parent_kind: str = "",
        extension_id: str = "",
        method: str = "",
        title: str = "",
        message: str = "",
        options: list[str] = [],
        placeholder: str = "",
        created: float = 0.0,
        timeout_ms: float = 30000.0,
        deadline_s: float = 0.0;
}

glob UI_METHODS: list[str] = ["select", "confirm", "input"];

def new_ui_queue -> UiInteractionQueue;

obj UiInteractionQueue {
    has lock: any = None,
        records: list[UiInteraction] = [],
        by_corr: dict[str, UiInteraction] = {},
        next_id: int = 1;
    def enqueue(req: dict[str, any]) -> list[any];
    def poll(now: float) -> list[any];
    def take(corr: str) -> UiInteraction | None;
    def cancel_by_parent(parent_corr: str) -> list[UiInteraction];
    def cancel_all -> int;

    def has_open(parent_corr: str) -> bool;
}
