"""Interactive UI round-trip queue (P12 slice 2).

Thread-safe FIFO of pending extension UI requests (ui.select/confirm/input)
that crossed the wire as `ui_request` envelopes. The reader thread enqueues;
the TUI mainloop polls the oldest live request, renders one modal at a time,
and answers through respond(); timeouts/cancellations reap records and hand
back the cancelled set so callers can emit `ui_response` envelopes.

Pure datastructure — no bridge, no I/O. Envelope emission lives in
plugin_bridge.jac wrappers so this stays unit-testable in isolation.
"""

import threading;


obj:pub UiInteraction {
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


def new_ui_queue() -> UiInteractionQueue {
    return UiInteractionQueue(lock=threading.Lock());
}


obj:pub UiInteractionQueue {
    has lock: threading.Lock = threading.Lock(),
        records: list[UiInteraction] = [],
        by_corr: dict[str, UiInteraction] = {},
        next_id: int = 1;

    """Validate + enqueue one request. Returns (ok, corr-or-error).

    corr comes from the request when supplied (the Node host owns child-id
    generation so ui_response/ui_cancel correlate); falls back to ui-N."""
    def enqueue(req: dict[str, any]) -> list[any] {
        method = str(req.get("method", ""));
        if method not in UI_METHODS {
            return [False, f"unsupported ui method {method}"];
        }
        if str(req.get("parent_corr", "")) == "" {
            return [False, "parent_correlation_id required"];
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
                created_f: float = req.get("created", 0.0) as float;
                timeout_f: float = req.get("timeout_ms", 30000.0) as float;
                options: list[str] = [];
                raw_options: any = req.get("options", []);
                if isinstance(raw_options, list) {
                    for option in raw_options as list[any] {
                        options.append(str(option));
                    }
                }
                rec = UiInteraction(
                    corr=corr,
                    parent_corr=str(req.get("parent_corr", "")),
                    parent_kind=str(req.get("parent_kind", "")),
                    extension_id=str(req.get("extension_id", "")),
                    method=method,
                    title=str(req.get("title", "")),
                    message=str(req.get("message", "")),
                    options=options,
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

    """Peek the oldest live record WITHOUT detaching it — the TUI polls
every tick and answers later via take(). Expired ones reap into element 2."""
    def poll(now: float) -> tuple[UiInteraction | None, list[UiInteraction]] {
        live: UiInteraction | None = None;
        expired: list[UiInteraction] = [];
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
        return (live, expired);
    }

    """Pop one record by child correlation (answer or explicit cancel)."""
    def take(corr: str) -> UiInteraction | None {
        self.lock.acquire();
        try {
                r: UiInteraction | None = self.by_corr.pop(corr, None);
                if r is not None {
                    self.records = [x for x in self.records if x.corr != corr];
                }
                return r;
        } finally {
            self.lock.release();
        }
    }

    """Cancel every open child of one parent; returns the cancelled records."""
    def cancel_by_parent(parent_corr: str) -> list[UiInteraction] {
        cancelled: list[UiInteraction] = [];
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

    """Cancel everything; returns how many."""
    def cancel_all() -> int {
        n = 0;
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

    def has_open(parent_corr: str) -> bool {
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
}
