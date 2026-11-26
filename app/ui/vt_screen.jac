glob _FG_NAMES: list[str] = ["black", "red", "green", "brown", "blue", "magenta", "cyan", "white"],
     _BRIGHT_NAMES: list[str] = [
         "brightblack",
         "brightred",
         "brightgreen",
         "brightbrown",
         "brightblue",
         "brightmagenta",
         "brightcyan",
         "brightwhite",
     ],
     _BASE16_HEX: list[str] = [
         "000000",
         "cd0000",
         "00cd00",
         "cdcd00",
         "0000ee",
         "cd00cd",
         "00cdcd",
         "e5e5e5",
         "7f7f7f",
         "ff0000",
         "00ff00",
         "ffff00",
         "5c5cff",
         "ff00ff",
         "00ffff",
         "ffffff",
     ];

obj VtCell {
    has data: str = " ",
        fg: str = "default",
        bg: str = "default",
        bold: bool = False,
        italics: bool = False,
        underscore: bool = False,
        reverse: bool = False;
}

def _hex2(v: int) -> str;
def _color256(n: int) -> str;

obj VtScreen {
    has columns: int = 80,
        rows: int = 24,
        history_max: int = 1000,
        buffer: list[list[VtCell]] = [],
        history: list[list[VtCell]] = [],
        cursor_x: int = 0,
        cursor_y: int = 0,
        cursor_hidden: bool = False,
        title: str = "",
        attrs: VtCell = VtCell(),
        scroll_top: int = 0,
        scroll_bottom: int = 23,
        saved_x: int = 0,
        saved_y: int = 0,
        saved_attrs: VtCell = VtCell(),
        state: str = "ground",
        seq: str = "",
        last_x: int = -1,
        last_y: int = -1;

    def init(columns: int = 80, rows: int = 24, history_max: int = 1000);

    def _blank -> VtCell;

    def _blank_line -> list[VtCell];

    def _clamp_cursor;

    def reset;
    def resize(rows: int, columns: int);

    def _push_history(line: list[VtCell]);

    def display -> list[str];
    def history_text(line: list[VtCell]) -> str;

    def _scroll_up(n: int);

    def _scroll_down(n: int);

    def index;

    def reverse_index;

    def _draw(ch: str);

    def _erase_cells(y: int, x0: int, x1: int);

    def _erase_display(how: int);

    def _erase_line(how: int);

    def _insert_lines(n: int);

    def _delete_lines(n: int);

    def _insert_chars(n: int);

    def _delete_chars(n: int);

    def _sgr(params: list[int]);

    def _csi(body: str);

    def _save_cursor;

    def _restore_cursor;

    def _osc(body: str);

    def feed(data: str);
}
