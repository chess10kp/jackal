def _open_picker(
    app: LiveShell,
    title: str,
    rows: list[str],
    ids: list[str],
    extra_last_input: bool = False,
    multi: bool = False,
) -> bool;
def _close_picker(app: LiveShell);
def _picker_filtered(p: dict[str, any]) -> tuple[list[str], list[str]];

def _multi_filtered(p: dict[str, any]) -> tuple[list[str], list[str]];
