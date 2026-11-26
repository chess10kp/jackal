def _open_window(app: LiveShell, win: WindowState, force: bool = False) -> bool;
def _close_top_window(app: LiveShell) -> bool;
def _handle_window_key(app: LiveShell, key: str) -> bool;
def _window_paint_lines(app: LiveShell) -> list[str] | None;

def _picker_state(app: LiveShell) -> any;

def _ui_modal_state(app: LiveShell) -> any;

def _approval_state(app: LiveShell) -> any;
