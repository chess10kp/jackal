"""Fake in-process plugin host — unit-test-only mirror of pi_shim.mjs.

Extracted from agent/plugin_bridge.jac: everything here exists ONLY for the
test path, an in-Jac stand-in for plugin_host/pi_shim.mjs used while no Node
sidecar is running. Import direction is one-way (plugin_bridge -> fake_host
-> protocol) so runtime imports of plugin_bridge stay unchanged.
"""

import time;

import from .protocol {
    Envelope,
    make_envelope,
}

# FakePluginHost lives in fake_host_types.jac (native-pinned so signatures
# taking it resolve in native units); re-exported here so existing
# `from .fake_host { FakePluginHost }` importers are unchanged.
import from .fake_host_types {
    FAKE_HOST_CAPS,
    FAKE_COMPAT_TIER,
    FakeCommandHandler,
    FakeMarkdownTransformer,
    FakeRenderer,
    FakeShortcutHandler,
    FakePluginHost,
    create_fake_host,
}
import from .plugin_bridge_model { PluginBridge }


"""Mark bridge activity (resets idle reap clock)."""
def touch_bridge(bridge: PluginBridge) {
    bridge.last_active = time.monotonic();
    if bridge.status_phase in ("idle", "ready", "") {
        bridge.status_phase = "ready";
    }
}


"""Apply host_hello payload onto bridge capability fields (P4).

Caps/tier are DERIVED from the received hello — never hand-copied constants."""
def apply_hello(bridge: PluginBridge, hello: Envelope) {
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


"""Attach an in-process host (lazy ensure). Emits host_hello into inbox.

Hello shape matches plugin_host/host.mjs byte-for-byte in structure:
{protocol, node, caps, compat, compat_label}."""
def:pub ensure_host(bridge: PluginBridge, host: FakePluginHost | None = None) -> str {
    if (
        bridge.host_kind == "node"
        and bridge.proc is not None
        and bridge.proc.poll() is None
    ) {
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


# ---- fake-host registrations (unit-test parity for the JS API surface) ----

"""Register a command handler on the FAKE host (unit-test path)."""
def:pub register_fake_command(
    bridge: PluginBridge,
    name: str,
    handler: Callable[[str, dict[str, any]], any],
    description: str = "",
    extension_id: str = "fake.commands",
) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    h.command_handlers[name] = FakeCommandHandler(fn=handler, owner=extension_id);
    bridge.commands[name] = {
        "name": name,
        "description": description,
        "extension_id": extension_id,
    };
}


def register_fake_shortcut(
    bridge: PluginBridge,
    key: str,
    handler: Callable[[dict[str, any]], any],
    description: str = "",
    extension_id: str = "fake.shortcuts",
) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    h.shortcut_handlers[key] = FakeShortcutHandler(fn=handler, owner=extension_id);
    bridge.shortcuts[key] = {
        "key": key,
        "description": description,
        "extension_id": extension_id,
    };
}


"""Register a lifecycle listener on the FAKE host (unit-test path)."""
def register_fake_listener(
    bridge: PluginBridge,
    event: str,
    handler: Callable[[dict[str, any], dict[str, any]], any],
) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    if event not in h.listeners {
        h.listeners[event] = [];
    }
    h.listeners[event].append(handler);
}


"""Register a markdown transformer on the FAKE host (unit-test path)."""
def register_fake_transformer(
    bridge: PluginBridge,
    fn: Callable[[str, dict[str, any]], any],
    extension_id: str = "fake.xform",
) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    h.md_transformers.append(FakeMarkdownTransformer(
        fn=fn, extension_id=extension_id
    ));
    bridge.md_transformers.append({"extension_id": extension_id});
}


"""Register a provider on the FAKE host (unit-test parity for registerProvider)."""
def register_fake_provider(bridge: PluginBridge, cfg: dict[str, any], extension_id: str = "fake.provider") {
    ensure_host(bridge);
    name = str(cfg.get("name", ""));
    if not name {
        raise ValueError("provider config requires a name");
    }
    h: FakePluginHost | None = bridge.host;
    provider_cfg: dict[str, any] = dict(cfg);
    if h is not None {
        owned_cfg: dict[str, any] = dict(provider_cfg);
        owned_cfg["owner"] = extension_id;
        h.providers[name] = owned_cfg;
    }
    provider_cfg["extension_id"] = extension_id;
    bridge.providers[name] = provider_cfg;
}


"""Register a renderer on the FAKE host (unit-test parity)."""
def register_fake_renderer(
    bridge: PluginBridge,
    kind: str,
    type: str,
    fn: Callable[[any], any],
    extension_id: str = "fake.renderer",
) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is None {
        raise RuntimeError("plugin host unavailable");
    }
    table = h.message_renderers if kind != "entry" else h.entry_renderers;
    table[str(type)] = FakeRenderer(fn=fn, owner=extension_id);
}


def fake_push_message(bridge: PluginBridge, role: str, content: str) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is not None {
        h.pending_messages.append({"role": role, "content": content});
    }
}


def fake_push_entry(bridge: PluginBridge, type: str, data: dict[str, any]) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is not None {
        h.pending_entries.append({"type": type, "data": data});
    }
}


def set_fake_active_tools(bridge: PluginBridge, names: list[str] | None) {
    ensure_host(bridge);
    h: FakePluginHost | None = bridge.host;
    if h is not None {
        h.active_tools = list(names) if names is not None else None;
    }
}


def fake_session_name(bridge: PluginBridge) -> str {
    return str(bridge.session_name);
}


"""Minimal UI surface handed to fake-host handlers; collects notifications
and display-method ui_events (parity with the JS makeUi surface)."""
obj FakeUi {
    has notifications: list[str],
        ui_events: list[dict[str, any]];

    def notify(message: str, level: str = "info") {
        self.notifications.append(str(message));
    }

    def _record(method: str, args: list[str]) {
        self.ui_events.append({"method": method, "args": args});
    }

    def set_status(owner: str, text: str) {
        self._record("setStatus", [text]);
    }

    def set_widget(id: str, text: str) {
        self._record("setWidget", [id, text]);
    }

    def set_footer(text: str) {
        self._record("setFooter", [text]);
    }

    def set_title(text: str) {
        self._record("setTitle", [text]);
    }

    def select(_title: str, _options: list[str]) -> any {
        return None;
    }

    def confirm(_message: str) -> bool {
        return False;
    }

    def input(_message: str, _default: str = "") -> str {
        return "";
    }
}
