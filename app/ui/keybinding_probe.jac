obj KeyProbeShell {
    has running: bool = True,
        dirty: bool = False,
        phase: str = "ready",
        status_hint: str = "",
        ui_modal: any = None,
        approval: any = None,
        tool_replies: list[str] = [];
}

def probe_handle_key(app: KeyProbeShell, key: str);
def make_key_probe(bindings: list[tuple[str, str]]) -> tuple[KeyProbeShell, any, list[str]];
def drop_key_probe(bridge: any);
