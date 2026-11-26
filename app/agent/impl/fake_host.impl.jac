impl touch_bridge(bridge: any) {
    bridge.last_active = time.monotonic();
    if bridge.status_phase in ("idle", "ready", "") {
        bridge.status_phase = "ready";
    }
}

impl apply_hello(bridge: any, hello: Envelope) {
    payload = hello.payload if hello.payload is not None else {};
    bridge.hello_payload = dict(payload);
    raw_caps: any = payload.get("caps", []);
    caps: list[str] = [];
    if isinstance(raw_caps, list) {
        caps = [str(c) for c in raw_caps];
    }
    bridge.host_caps = caps;
    tier = str(payload.get("compat", "") or "");
    if not tier {
        if "cancel" in caps or "updates" in caps {
            tier = "T1";
        } else {
            tier = "T0";
        }
    }
    bridge.compat_tier = tier;
}

impl ensure_host(bridge: any, host: FakePluginHost | None = None) -> str {
    if (bridge.host_kind == "node" and bridge.proc is not None and bridge.proc.poll() is None) {
        return "ready";
    }
    if bridge.host is not None and bridge.host.alive {
        return "ready";
    }
    h = host if host is not None else create_fake_host();
    bridge.host = h;
    bridge.host_kind = "fake";
    h.alive = True;
    hello = make_envelope(
        kind="host_hello",
        session_id=bridge.session_id,
        payload={
            "protocol": 1,
            "node": h.node_version,
            "caps": list(h.caps),
            "compat": h.compat_tier,
            "compat_label": "Pi tool-extension compatibility",
        },
    );
    bridge.inbox.append(hello);
    apply_hello(bridge, hello);
    touch_bridge(bridge);
    bridge.status_phase = "ready";
    return "ready";
}

impl register_fake_command(
    bridge: any, name: str, handler: any, description: str = "", extension_id: str = "fake.commands"
) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    h.command_handlers[name] = {"handler": handler, "owner": extension_id};
    bridge.commands[name] = {
        "name": name,
        "description": description,
        "extension_id": extension_id,
    };
}

impl register_fake_shortcut(
    bridge: any, key: str, handler: any, description: str = "", extension_id: str = "fake.shortcuts"
) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    h.shortcut_handlers[key] = {"handler": handler, "owner": extension_id};
    bridge.shortcuts[key] = {"key": key, "description": description, "extension_id": extension_id};
}

impl register_fake_listener(bridge: any, event: str, handler: any) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    if event not in h.listeners {
        h.listeners[event] = [];
    }
    h.listeners[event].append(handler);
}

impl register_fake_transformer(bridge: any, fn: any, extension_id: str = "fake.xform") {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    transformer = {"fn": fn, "extension_id": extension_id};
    h.md_transformers.append(transformer);
    bridge.md_transformers.append(transformer);
}

impl register_fake_provider(bridge: any, cfg: dict[str, any], extension_id: str = "fake.provider") {
    ensure_host(bridge);
    name = str(cfg.get("name", ""));
    if not name {
        raise ValueError("provider config requires a name");
    }
    h: FakePluginHost = bridge.host;
    provider_cfg = dict(cfg);
    if h is not None {
        h.providers[name] = {**provider_cfg, "owner": extension_id};
    }
    provider_cfg["extension_id"] = extension_id;
    bridge.providers[name] = provider_cfg;
}

impl register_fake_renderer(
    bridge: any, kind: str, renderer_type: str, fn: any, extension_id: str = "fake.renderer"
) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    table = h.message_renderers if kind != "entry" else h.entry_renderers;
    table[str(renderer_type)] = {"fn": fn, "owner": extension_id};
}

impl fake_push_message(bridge: any, role: str, content: str) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is not None {
        h.pending_messages.append({"role": role, "content": content});
    }
}

impl fake_push_entry(bridge: any, entry_type: str, data: dict[str, any]) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is not None {
        h.pending_entries.append({"type": entry_type, "data": data});
    }
}

impl set_fake_active_tools(bridge: any, names: list[str] | None) {
    ensure_host(bridge);
    h: FakePluginHost = bridge.host;
    if h is not None {
        h.active_tools = list(names) if names is not None else None;
    }
}

impl fake_session_name(bridge: any) -> str {
    return str(bridge.session_name);
}

impl FakeUi.notify(message: str, level: str = "info") {
    self.notifications.append(str(message));
}

impl FakeUi._record(method: str, args: list[str]) {
    self.ui_events.append({"method": method, "args": args});
}

impl FakeUi.set_status(owner: str, text: str) {
    self._record("setStatus", [text]);
}

impl FakeUi.set_widget(id: str, text: str) {
    self._record("setWidget", [id, text]);
}

impl FakeUi.set_footer(text: str) {
    self._record("setFooter", [text]);
}

impl FakeUi.set_title(text: str) {
    self._record("setTitle", [text]);
}

impl FakeUi.select(_title: str, _options: list[str]) -> any {
    return None;
}

impl FakeUi.confirm(_message: str) -> bool {
    return False;
}

impl FakeUi.input(_message: str, _default: str = "") -> str {
    return "";
}
