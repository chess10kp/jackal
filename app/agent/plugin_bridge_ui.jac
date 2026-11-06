"""Plugin bridge public interactive UI operations."""

import time;
import from .plugin_bridge_core { PluginBridge }
import from .interactions { UiInteraction, UiInteractionQueue }
import from .plugin_bridge_io { _ui_queue, _ui_send_response }

def:pub poll_ui_request(bridge: PluginBridge) -> dict[str, any] | None {
    if bridge is None or bridge.ui_q is None {
        return None;
    }
    q = bridge.ui_q as UiInteractionQueue;
    polled: tuple[UiInteraction | None, list[UiInteraction]] = q.poll(time.monotonic());
    live: UiInteraction | None = polled[0];
    expired: list[UiInteraction] = polled[1];
    for r in expired {
        _ui_send_response(bridge, r.corr, "cancelled", None, "timeout");
    }
    if live is None {
        return None;
    }
    return {
        "corr": live.corr,
        "parent_corr": live.parent_corr,
        "parent_kind": live.parent_kind,
        "extension_id": live.extension_id,
        "method": live.method,
        "title": live.title,
        "message": live.message,
        "options": list(live.options),
        "placeholder": live.placeholder,
    };
}


"""Answer one pending request. select/input pass strings, confirm passes
bool. Unknown/expired corr is ignored (idempotent)."""
def:pub respond_ui(bridge: PluginBridge, corr: str, value: any) -> bool {
    if bridge is None or bridge.ui_q is None {
        return False;
    }
    r: UiInteraction | None = (bridge.ui_q as UiInteractionQueue).take(str(corr));
    if r is None {
        return False;
    }
    return _ui_send_response(bridge, str(r.corr), "ok", value);
}


"""Cancel one pending request by child correlation."""
def:pub cancel_ui(bridge: PluginBridge, corr: str, reason: str = "cancelled") -> bool {
    if bridge is None or bridge.ui_q is None {
        return False;
    }
    r: UiInteraction | None = (bridge.ui_q as UiInteractionQueue).take(str(corr));
    if r is None {
        return False;
    }
    return _ui_send_response(bridge, str(r.corr), "cancelled", None, reason);
}


"""Cancel every open request (turn abort / dispose). Returns count."""
def:pub cancel_all_ui(bridge: PluginBridge, reason: str = "cancelled") -> int {
    if bridge is None or bridge.ui_q is None {
        return 0;
    }
    q = bridge.ui_q as UiInteractionQueue;
    n = 0;
    # Drain via take() so queue and wire stay consistent.
    while True {
        polled2: tuple[UiInteraction | None, list[UiInteraction]] = q.poll(time.monotonic());
        live: UiInteraction | None = polled2[0];
        expired: list[UiInteraction] = polled2[1];
        if len(expired) == 0 and live is None {
            break;
        }
        for r in expired {
            _ui_send_response(bridge, r.corr, "cancelled", None, reason);
            n += 1;
        }
        # poll() is a peek: only expired records are detached automatically.
        # Detach the live record explicitly or this loop spins until its
        # deadline lapses.
        if live is not None {
            _ui_send_response(bridge, live.corr, "cancelled", None, reason);
            n += 1;
            q.take(str(live.corr));
        }
    }
    return n;
}
