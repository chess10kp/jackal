obj WindowSpec {
    has title: str = "",
        width: int = 46,
        hint: str = "",
        max_rows: int = 8;
}

obj WindowState {
    has spec: WindowSpec,
        kind: str = "window",
        payload: any = None,
        rows: list[str] = [],
        ids: list[str] = [],
        selected: int = -1,
        keys: dict[str, str] = {},
        on_action: any = None,
        refresh: any = None;
}

def _wpad(text: str, width: int) -> str;
def window_frame(spec: WindowSpec, body: list[str]) -> list[str];
def window_view(rows: list[str], selected: int, max_rows: int) -> tuple[list[str], int];
def window_lines(state: WindowState) -> list[str];
