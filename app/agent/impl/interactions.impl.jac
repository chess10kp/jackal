impl new_ui_queue -> UiInteractionQueue {
    return UiInteractionQueue(lock=threading.Lock());
}

impl UiInteractionQueue.enqueue(req: dict[str, any]) -> list[any] {
    method = str(req.get("method", ""));
    if method not in UI_METHODS {
        return [False, f"unsupported ui method {method}"];
    }
    if str(req.get("parent_corr", "")) == "" {
        return [False, "parent_correlation_id required"];
    }
    if self.lock is None {
        self.lock = threading.Lock();
    }
    self.lock.acquire();
    try {
        corr = str(req.get("corr", ""));
        if corr == "" {
            corr = f"ui-{self.next_id}";
            self.next_id += 1;
        }
        if corr in self.by_corr {
            return [False, f"duplicate correlation {corr}"];
        }
        created_f: float = float(req.get("created", 0.0));
        timeout_f: float = float(req.get("timeout_ms", 30000.0));
        rec = UiInteraction(
            corr=corr,
            parent_corr=str(req.get("parent_corr", "")),
            parent_kind=str(req.get("parent_kind", "")),
            extension_id=str(req.get("extension_id", "")),
            method=method,
            title=str(req.get("title", "")),
            message=str(req.get("message", "")),
            options=[str(o) for o in req.get("options", [])]
                if isinstance(req.get("options"), list)
                else [],
            placeholder=str(req.get("placeholder", "")),
            created=created_f,
            timeout_ms=timeout_f,
            deadline_s=created_f + timeout_f / 1000.0,
        );
        self.records.append(rec);
        self.by_corr[corr] = rec;
        return [True, corr];
    } finally {
        self.lock.release();
    }
}

impl UiInteractionQueue.poll(now: float) -> list[any] {
    live: UiInteraction | None = None;
    expired: list[UiInteraction] = [];
    if self.lock is None {
        return [None, []];
    }
    self.lock.acquire();
    try {
        remaining: list[UiInteraction] = [];
        for r in self.records {
            if r.deadline_s <= now {
                expired.append(r);
                self.by_corr.pop(r.corr, None);
            } else {
                remaining.append(r);
                if live is None {
                    live = r;
                }
            }
        }
        self.records = remaining;
    } finally {
        self.lock.release();
    }
    return [live, expired];
}

impl UiInteractionQueue.take(corr: str) -> UiInteraction | None {
    if self.lock is None {
        return None;
    }
    self.lock.acquire();
    try {
        r: any = self.by_corr.pop(corr, None);
        if r is not None {
            self.records = [x for x in self.records if x.corr != corr];
        }
        return r;
    } finally {
        self.lock.release();
    }
}

impl UiInteractionQueue.cancel_by_parent(parent_corr: str) -> list[UiInteraction] {
    cancelled: list[UiInteraction] = [];
    if self.lock is None {
        return cancelled;
    }
    self.lock.acquire();
    try {
        remaining: list[UiInteraction] = [];
        for r in self.records {
            if r.parent_corr == parent_corr {
                cancelled.append(r);
                self.by_corr.pop(r.corr, None);
            } else {
                remaining.append(r);
            }
        }
        self.records = remaining;
    } finally {
        self.lock.release();
    }
    return cancelled;
}

impl UiInteractionQueue.cancel_all -> int {
    n = 0;
    if self.lock is None {
        return n;
    }
    self.lock.acquire();
    try {
        n = len(self.records);
        self.records.clear();
        self.by_corr.clear();
    } finally {
        self.lock.release();
    }
    return n;
}

impl UiInteractionQueue.has_open(parent_corr: str) -> bool {
    if self.lock is None {
        return False;
    }
    self.lock.acquire();
    try {
        for r in self.records {
            if r.parent_corr == parent_corr {
                return True;
            }
        }
    } finally {
        self.lock.release();
    }
    return False;
}
