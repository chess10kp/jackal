impl _absorb_payload(bridge: any, payload: dict[str, any]) {
    msgs: any = payload.get("messages", []);
    if isinstance(msgs, list) {
        for m in msgs {
            if isinstance(m, dict) {
                bridge.traffic_messages.append({
                    "role": str(m.get("role", "user")),
                    "content": str(m.get("content", "")),
                });
            }
        }
    }
    ents: any = payload.get("entries", []);
    if isinstance(ents, list) {
        for e in ents {
            if isinstance(e, dict) {
                bridge.traffic_entries.append(dict(e));
            }
        }
    }
    uis: any = payload.get("ui_events", []);
    if isinstance(uis, list) {
        for u in uis {
            if isinstance(u, dict) {
                bridge.traffic_entries.append({
                    "type": "ui_event",
                    "method": str(u.get("method", "")),
                    "args": u.get("args", []),
                });
            }
        }
    }
    sn = payload.get("session_name", "");
    if sn {
        bridge.session_name = str(sn);
    }
    provs: any = payload.get("providers", []);
    if isinstance(provs, list) {
        for p in provs {
            if isinstance(p, dict) and p.get("name") {
                cfg = dict(p);
                cfg["extension_id"] = str(payload.get("id", ""));
                bridge.providers[str(p.get("name"))] = cfg;
            }
        }
    }
    scs: any = payload.get("shortcuts", []);
    if isinstance(scs, list) {
        for sc in scs {
            if isinstance(sc, dict) and sc.get("key") {
                meta = dict(sc);
                meta["extension_id"] = str(payload.get("id", ""));
                bridge.shortcuts[str(sc.get("key"))] = meta;
            }
        }
    }
    lbs: any = payload.get("labels", []);
    if isinstance(lbs, list) {
        for lb in lbs {
            if isinstance(lb, dict) and lb.get("id") {
                lmeta = dict(lb);
                lmeta["extension_id"] = str(payload.get("id", ""));
                bridge.labels[str(lb.get("id"))] = lmeta;
            }
        }
    }
    msel = payload.get("model_select", "");
    if msel {
        bridge.pending_model = str(msel);
    }
    tlsel = payload.get("thinking_level_select", "");
    if tlsel {
        bridge.pending_thinking_level = str(tlsel);
    }
}

impl list_shortcuts(bridge: any | None) -> dict[str, any] {
    if bridge is None {
        return {};
    }
    return dict(bridge.shortcuts);
}

impl list_labels(bridge: any | None) -> dict[str, any] {
    if bridge is None {
        return {};
    }
    return dict(bridge.labels);
}

impl drain_model_requests(bridge: any | None) -> dict[str, any] {
    out: dict[str, any] = {"model": "", "thinking_level": ""};
    if bridge is None {
        return out;
    }
    out["model"] = bridge.pending_model;
    out["thinking_level"] = bridge.pending_thinking_level;
    bridge.pending_model = "";
    bridge.pending_thinking_level = "";
    return out;
}

impl _absorb_pending_fake(bridge: any, h: FakePluginHost) {
    if h.pending_messages {
        msgs = h.pending_messages;
        h.pending_messages = [];
        _absorb_payload(bridge, {"messages": msgs});
    }
    if h.pending_entries {
        ents = h.pending_entries;
        h.pending_entries = [];
        _absorb_payload(bridge, {"entries": ents});
    }
}
