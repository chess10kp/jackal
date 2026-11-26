glob KEY_SEQUENCES: dict[str, str] = {
    "enter": "\r",
    "escape": "\x1b",
    "esc": "\x1b",
    "tab": "\t",
    "backspace": "\x7f",
    "space": " ",
    "up": "\x1b[A",
    "down": "\x1b[B",
    "right": "\x1b[C",
    "left": "\x1b[D",
    "home": "\x1b[H",
    "end": "\x1b[F",
    "page_up": "\x1b[5~",
    "page_down": "\x1b[6~",
    "delete": "\x1b[3~",
    "shift+tab": "\x1b[Z",
    "ctrl+a": "\x01",
    "ctrl+c": "\x03",
    "ctrl+d": "\x04",
    "ctrl+e": "\x05",
    "ctrl+k": "\x0b",
    "ctrl+l": "\x0c",
    "ctrl+u": "\x15",
    "ctrl+w": "\x17",
};

obj EmulatedTerminal(Terminal) {
    has screen: VtScreen = VtScreen(),
        input_queue: list[str] = [],
        title: str = "",
        bytes_written: int = 0,
        write_count: int = 0;

    def init(columns: int = 80, rows: int = 24, scrollback: int = 1000);

    def write(data: str);

    def move_cursor(row: int, col: int);

    def start;

    def stop;
    def poll_input(timeout_s: float = 0.0) -> str;
    def send_input(data: str);
    def send_key(key: str);
    def send_paste(text: str);
    def resize(columns: int, rows: int);
    def close_input;
    def viewport -> list[str];

    def viewport_text -> str;
    def scroll_buffer -> list[str];
    def cursor -> tuple[int, int];
    def cell(row: int, col: int) -> dict[str, any];
    def find(needle: str) -> tuple[int, int] | None;
    def line_with(needle: str) -> str;
    def reset_screen;
}
