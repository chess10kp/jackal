impl create_queue -> ApprovalQueue {
    return ApprovalQueue();
}

impl request_approval(
    queue: ApprovalQueue, tool_name: str, cmd: str, mode: str, now_ms: float
) -> dict[str, any] {
    policy = requires_approval(mode, tool_name, cmd);
    if policy == "auto" {
        return {"decision": "auto", "tool_name": tool_name, "mode": mode};
    }
    if policy == "blocked" {
        return {"decision": "blocked", "tool_name": tool_name, "mode": mode};
    }
    pa = PendingApproval(
        id="approval-" + str(queue.next_seq),
        tool_name=tool_name,
        cmd=cmd.strip(),
        mode=mode,
        created_at=now_ms,
    );
    queue.next_seq += 1;
    queue.items.append(pa);
    return {"decision": "pending", "id": pa.id};
}

impl resolve(queue: ApprovalQueue, id: str, approved: bool) -> dict[str, any] {
    idx = -1;
    for i in range(len(queue.items)) {
        if queue.items[i].id == id {
            idx = i;
            break;
        }
    }
    if idx < 0 {
        return {"error": "unknown_approval_id", "id": id};
    }
    queue.items.pop(idx);
    return {"id": id, "approved": approved};
}

impl pending(queue: ApprovalQueue) -> PendingApproval | None {
    if len(queue.items) == 0 {
        return None;
    }
    return queue.items[0];
}

impl cancel_all(queue: ApprovalQueue) -> int {
    n = len(queue.items);
    queue.items.clear();
    return n;
}

impl expire_older_than(queue: ApprovalQueue, now_ms: float, max_age_ms: float) -> int {
    cutoff = now_ms - max_age_ms;
    keep: list[PendingApproval] = [];
    dropped = 0;
    for rec in queue.items {
        if rec.created_at >= cutoff {
            keep.append(rec);
        } else {
            dropped += 1;
        }
    }
    queue.items = keep;
    return dropped;
}
