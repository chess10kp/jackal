obj PendingApproval {
    has id: str = "",
        tool_name: str = "",
        cmd: str = "",
        mode: str = "",
        created_at: float = 0.0;
}

obj ApprovalQueue {
    has items: list[PendingApproval] = [],
        next_seq: int = 1;
}

def create_queue -> ApprovalQueue;
def request_approval(
    queue: ApprovalQueue, tool_name: str, cmd: str, mode: str, now_ms: float
) -> dict[str, any];
def resolve(queue: ApprovalQueue, id: str, approved: bool) -> dict[str, any];
def pending(queue: ApprovalQueue) -> PendingApproval | None;
def cancel_all(queue: ApprovalQueue) -> int;
def expire_older_than(queue: ApprovalQueue, now_ms: float, max_age_ms: float) -> int;
