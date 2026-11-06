"""FakePluginHost type + factory — native unit.

Split from agent/fake_host.jac so the host obj registers a native layout:
the bridge-touching helpers stay in fake_host.jac (server; `bridge: any`
receivers and the make_envelope boundary cannot lower). Pinned native in
jac.toml; server callers construct through create_fake_host because a
native-pinned obj class cannot be constructed by server code directly
(class-boundary wall, see agent.tool_spec / make_tool_spec).
"""

# Mirror of plugin_host/pi_shim.mjs HOST_CAPS / COMPAT_TIER: the fake host
# advertises the same surfaces in its host_hello as the real shim so the
# bridge derives identical capability state from either hello.
glob FAKE_HOST_CAPS: list[str] = [
         "tools",
         "cancel",
         "updates",
         "commands",
         "session_hooks",
         "transformers",
         "providers",
         "renderers",
     ],
     FAKE_COMPAT_TIER: str = "T2-partial";

obj:pub FakeMarkdownTransformer {
    has fn: Callable[[str, dict[str, any]], any],
        extension_id: str;
}

obj:pub FakeRenderer {
    has fn: Callable[[any], any],
        owner: str;
}

obj:pub FakeCommandHandler {
    has fn: Callable[[str, dict[str, any]], any],
        owner: str;
}

obj:pub FakeShortcutHandler {
    has fn: Callable[[dict[str, any]], any],
        owner: str;
}


obj:pub FakePluginHost {
    has handlers: dict[str, Callable[[dict[str, any]], any]] = {},
        command_handlers: dict[str, FakeCommandHandler] = {},
        shortcut_handlers: dict[str, FakeShortcutHandler] = {},
        listeners: dict[str, list[Callable[[dict[str, any], dict[str, any]], any]]] = {},
        md_transformers: list[FakeMarkdownTransformer] = [],
        pending_messages: list[dict[str, any]] = [],
        pending_entries: list[dict[str, any]] = [],
        active_tools: list[str] | None = None,
        session_name: str = "",
        providers: dict[str, dict[str, any]] = {},
        message_renderers: dict[str, FakeRenderer] = {},
        entry_renderers: dict[str, FakeRenderer] = {},
        extension_tools: dict[str, list[str]] = {},
        cancelled: set[str] = set(),
        node_version: str = "fake",
        alive: bool = True,
        caps: list[str] = list(FAKE_HOST_CAPS),
        compat_tier: str = FAKE_COMPAT_TIER;
}


def create_fake_host(node_version: str = "fake") -> FakePluginHost {
    return FakePluginHost(node_version=node_version);
}
