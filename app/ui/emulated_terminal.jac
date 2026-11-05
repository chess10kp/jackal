"""Jac VT screen used by the in-process TUI and PTY test harnesses.

This adapter keeps the small terminal surface the shell uses while interpreting
the ANSI cursor, erase, SGR, wrap, scroll, and title sequences emitted by the
renderer. It is implemented in Jac so test support does not depend on a Python
terminal package.
"""

import from ui.terminal {
    Terminal,
    ENTER_ALT_SCREEN,
    LEAVE_ALT_SCREEN,
    ENABLE_BRACKETED_PASTE,
    DISABLE_BRACKETED_PASTE,
    SYNC_BEGIN,
    SYNC_END,
    HIDE_CURSOR,
    SHOW_CURSOR,
}


"""Named keys for send_key (xterm sequences, as ProcessTerminal receives them)."""
glob KEY_SEQUENCES: dict[str, str] = {
    "enter": "\r", "escape": "\x1b", "esc": "\x1b", "tab": "\t",
    "backspace": "\x7f", "space": " ",
    "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
    "home": "\x1b[H", "end": "\x1b[F", "page_up": "\x1b[5~", "page_down": "\x1b[6~",
    "delete": "\x1b[3~", "shift+tab": "\x1b[Z",
    "ctrl+a": "\x01", "ctrl+c": "\x03", "ctrl+d": "\x04", "ctrl+e": "\x05",
    "ctrl+k": "\x0b", "ctrl+l": "\x0c", "ctrl+u": "\x15", "ctrl+w": "\x17",
};


obj TerminalCell {
    has data: str = " ",
        fg: str = "default",
        bg: str = "default",
        bold: bool = False,
        italics: bool = False,
        underscore: bool = False,
        reverse: bool = False;
}


obj EmulatedTerminal(Terminal) {
    has cells: list[list[TerminalCell]] = [],
        input_queue: list[str] = [],
        history: list[str] = [],
        scrollback_limit: int = 1000,
        title: str = "",
        bytes_written: int = 0,
        write_count: int = 0,
        cursor_x: int = 0,
        cursor_y: int = 0,
        current_fg: str = "default",
        current_bg: str = "default",
        current_bold: bool = False,
        current_italics: bool = False,
        current_underscore: bool = False,
        current_reverse: bool = False,
        wrap_pending: bool = False;

    def init(columns: int = 80, rows: int = 24, scrollback: int = 1000) {
        self.columns = max(1, columns);
        self.rows = max(1, rows);
        self.scrollback_limit = max(0, scrollback);
        self.cells = [];
        self.input_queue = [];
        self.history = [];
        self.title = "";
        self.bytes_written = 0;
        self.write_count = 0;
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.current_fg = "default";
        self.current_bg = "default";
        self.current_bold = False;
        self.current_italics = False;
        self.current_underscore = False;
        self.current_reverse = False;
        self.wrap_pending = False;
        self.eof = False;
        self.started = False;
        self.restored = True;
        self.alternate_screen = False;
        self.bracketed_paste = False;
        self.cursor_visible = True;
        self.sync_active = False;
        self._reset_cells();
    }

    def _blank_cell() -> TerminalCell {
        return TerminalCell();
    }

    def _blank_row() -> list[TerminalCell] {
        row: list[TerminalCell] = [];
        for _i in range(self.columns) {
            row.append(self._blank_cell());
        }
        return row;
    }

    def _reset_cells() {
        grid: list[list[TerminalCell]] = [];
        for _r in range(self.rows) {
            grid.append(self._blank_row());
        }
        self.cells = grid;
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.wrap_pending = False;
    }

    def _row_text(row: list[TerminalCell]) -> str {
        text: str = "";
        for c in row {
            text += c.data;
        }
        return text.rstrip();
    }

    def _scroll_up() {
        if self.cells {
            if self.scrollback_limit > 0 {
                self.history.append(self._row_text(self.cells[0]));
                while len(self.history) > self.scrollback_limit {
                    self.history.pop(0);
                }
            }
            self.cells.pop(0);
        }
        self.cells.append(self._blank_row());
        self.cursor_y = self.rows - 1;
    }

    def _line_feed() {
        self.wrap_pending = False;
        self.cursor_y += 1;
        if self.cursor_y >= self.rows {
            self._scroll_up();
        }
    }

    def _char_width(ch: str) -> int {
        if not ch {
            return 0;
        }
        cp: int = ord(ch[0]);
        if cp < 32 or (cp >= 0x300 and cp <= 0x36F) {
            return 0;
        }
        if (cp >= 0x1100 and cp <= 0x115F) or
           (cp >= 0x2E80 and cp <= 0xA4CF) or
           (cp >= 0xAC00 and cp <= 0xD7A3) or
           (cp >= 0xF900 and cp <= 0xFAFF) or
           (cp >= 0xFE10 and cp <= 0xFE6F) or
           (cp >= 0xFF01 and cp <= 0xFF60) or
           (cp >= 0x1F300 and cp <= 0x1FAFF) {
            return 2;
        }
        return 1;
    }

    def _put_char(ch: str) {
        width: int = self._char_width(ch);
        if width == 0 {
            if self.cursor_x > 0 and self.cursor_y >= 0 and self.cursor_y < self.rows {
                cell: TerminalCell = self.cells[self.cursor_y][min(self.cursor_x, self.columns) - 1];
                cell.data += ch;
            }
            return;
        }
        if self.wrap_pending or self.cursor_x + width > self.columns {
            self.cursor_x = 0;
            self._line_feed();
        }
        if self.cursor_y < 0 or self.cursor_y >= self.rows {
            return;
        }
        if self.cursor_x < 0 or self.cursor_x >= self.columns {
            return;
        }
        c: TerminalCell = TerminalCell(
            data=ch,
            fg=self.current_fg,
            bg=self.current_bg,
            bold=self.current_bold,
            italics=self.current_italics,
            underscore=self.current_underscore,
            reverse=self.current_reverse,
        );
        self.cells[self.cursor_y][self.cursor_x] = c;
        if width == 2 and self.cursor_x + 1 < self.columns {
            filler: TerminalCell = TerminalCell(
                data=" ", fg=self.current_fg, bg=self.current_bg,
                bold=self.current_bold, italics=self.current_italics,
                underscore=self.current_underscore, reverse=self.current_reverse,
            );
            self.cells[self.cursor_y][self.cursor_x + 1] = filler;
        }
        self.cursor_x += width;
        self.wrap_pending = self.cursor_x >= self.columns;
        if self.wrap_pending {
            self.cursor_x = self.columns - 1;
        }
    }

    def _erase_line(mode: int) {
        if self.cursor_y < 0 or self.cursor_y >= self.rows {
            return;
        }
        start: int = 0;
        end: int = self.columns;
        if mode == 0 { start = min(self.cursor_x, self.columns); }
        elif mode == 1 { end = min(self.cursor_x + 1, self.columns); }
        elif mode == 2 { start = 0; end = self.columns; }
        for x in range(start, end) {
            self.cells[self.cursor_y][x] = self._blank_cell();
        }
    }

    def _erase_display(mode: int) {
        if mode == 2 or mode == 3 {
            self._reset_cells();
            if mode == 3 { self.history = []; }
            return;
        }
        if mode == 0 {
            self._erase_line(0);
            for y in range(self.cursor_y + 1, self.rows) {
                self.cells[y] = self._blank_row();
            }
        } elif mode == 1 {
            for y in range(0, self.cursor_y) {
                self.cells[y] = self._blank_row();
            }
            self._erase_line(1);
        }
    }

    def _color(code: int) -> str {
        if code == 30 or code == 40 { return "black"; }
        if code == 31 or code == 41 { return "red"; }
        if code == 32 or code == 42 { return "green"; }
        if code == 33 or code == 43 { return "brown"; }
        if code == 34 or code == 44 { return "blue"; }
        if code == 35 or code == 45 { return "magenta"; }
        if code == 36 or code == 46 { return "cyan"; }
        if code == 37 or code == 47 { return "white"; }
        if code == 90 or code == 100 { return "brightblack"; }
        if code == 91 or code == 101 { return "brightred"; }
        if code == 92 or code == 102 { return "brightgreen"; }
        if code == 93 or code == 103 { return "brightyellow"; }
        if code == 94 or code == 104 { return "brightblue"; }
        if code == 95 or code == 105 { return "brightmagenta"; }
        if code == 96 or code == 106 { return "brightcyan"; }
        if code == 97 or code == 107 { return "brightwhite"; }
        return "default";
    }

    def _apply_sgr(params: list[int]) {
        if not params { params = [0]; }
        for code in params {
            if code == 0 {
                self.current_fg = "default"; self.current_bg = "default";
                self.current_bold = False; self.current_italics = False;
                self.current_underscore = False; self.current_reverse = False;
            } elif code == 1 { self.current_bold = True; }
            elif code == 3 { self.current_italics = True; }
            elif code == 4 { self.current_underscore = True; }
            elif code == 7 { self.current_reverse = True; }
            elif code == 22 { self.current_bold = False; }
            elif code == 23 { self.current_italics = False; }
            elif code == 24 { self.current_underscore = False; }
            elif code == 27 { self.current_reverse = False; }
            elif code >= 30 and code <= 37 or (code >= 90 and code <= 97) {
                self.current_fg = self._color(code);
            } elif code == 39 { self.current_fg = "default"; }
            elif code >= 40 and code <= 47 or (code >= 100 and code <= 107) {
                self.current_bg = self._color(code);
            } elif code == 49 { self.current_bg = "default"; }
        }
    }

    def _parse_params(body: str) -> list[int] {
        params: list[int] = [];
        if not body { return params; }
        for part in body.split(";") {
            p: str = part;
            if p.startswith("?") or p.startswith(">") {
                p = p[1:];
            }
            params.append(int(p) if p else 0);
        }
        return params;
    }

    def _apply_csi(body: str, final: str) {
        params: list[int] = self._parse_params(body);
        first: int = params[0] if params else 0;
        if final == "H" or final == "f" {
            row: int = params[0] if len(params) > 0 and params[0] > 0 else 1;
            col: int = params[1] if len(params) > 1 and params[1] > 0 else 1;
            self.cursor_y = min(max(0, row - 1), self.rows - 1);
            self.cursor_x = min(max(0, col - 1), self.columns - 1);
            self.wrap_pending = False;
        } elif final == "A" { self.cursor_y = max(0, self.cursor_y - max(1, first)); }
        elif final == "B" { self.cursor_y = min(self.rows - 1, self.cursor_y + max(1, first)); }
        elif final == "C" { self.cursor_x = min(self.columns - 1, self.cursor_x + max(1, first)); }
        elif final == "D" { self.cursor_x = max(0, self.cursor_x - max(1, first)); }
        elif final == "G" { self.cursor_x = min(self.columns - 1, max(0, first - 1)); }
        elif final == "d" { self.cursor_y = min(self.rows - 1, max(0, first - 1)); }
        elif final == "J" { self._erase_display(first); }
        elif final == "K" { self._erase_line(first); }
        elif final == "m" { self._apply_sgr(params); }
        elif final == "S" {
            for _i in range(max(1, first)) { self._scroll_up(); }
        } elif final == "h" and body == "?1049" { self.alternate_screen = True; }
        elif final == "l" and body == "?1049" { self.alternate_screen = False; }
        elif final == "h" and body == "?2004" { self.bracketed_paste = True; }
        elif final == "l" and body == "?2004" { self.bracketed_paste = False; }
        elif final == "h" and body == "?2026" { self.sync_active = True; }
        elif final == "l" and body == "?2026" { self.sync_active = False; }
        elif final == "h" and body == "?25" { self.cursor_visible = False; }
        elif final == "l" and body == "?25" { self.cursor_visible = True; }
    }

    def write(data: str) -> None {
        if not data { return; }
        self.write_count += 1;
        self.bytes_written += len(data);
        i: int = 0;
        while i < len(data) {
            ch: str = data[i];
            if ch == "\x1b" {
                if data.startswith("\x1b]", i) {
                    j: int = i + 2;
                    while j < len(data) and data[j] != "\x07" and not data.startswith("\x1b\\", j) { j += 1; }
                    if j < len(data) {
                        osc: str = data[i + 2:j];
                        if osc.startswith("0;") or osc.startswith("2;") { self.title = osc[2:]; }
                        i = j + (2 if data.startswith("\x1b\\", j) else 1);
                    } else { i = len(data); }
                    continue;
                }
                if data.startswith("\x1b[", i) {
                    j = i + 2;
                    while j < len(data) and (ord(data[j]) < 64 or ord(data[j]) > 126) { j += 1; }
                    if j < len(data) {
                        body: str = data[i + 2:j];
                        final: str = data[j];
                        if final == "H" and body == "" { self.cursor_x = 0; self.cursor_y = 0; }
                        else { self._apply_csi(body, final); }
                        i = j + 1;
                    } else { i = len(data); }
                    continue;
                }
                i += 1;
                continue;
            }
            if ch == "\n" { self._line_feed(); i += 1; continue; }
            if ch == "\r" { self.cursor_x = 0; self.wrap_pending = False; i += 1; continue; }
            if ch == "\b" { self.cursor_x = max(0, self.cursor_x - 1); self.wrap_pending = False; i += 1; continue; }
            if ch == "\t" {
                self.cursor_x = min(self.columns - 1, ((self.cursor_x // 8) + 1) * 8);
                i += 1; continue;
            }
            if ord(ch) >= 32 { self._put_char(ch); }
            i += 1;
        }
    }

    def move_cursor(row: int, col: int) -> None { self.write(f"\x1b[{row};{col}H"); }

    def start() -> None {
        if self.started { return; }
        self.write(ENABLE_BRACKETED_PASTE);
        self.write(ENTER_ALT_SCREEN);
        self.write(HIDE_CURSOR);
        self.started = True;
        self.restored = False;
    }

    def stop() -> None {
        if self.restored and not self.started { return; }
        if self.sync_active { self.write(SYNC_END); }
        if self.bracketed_paste { self.write(DISABLE_BRACKETED_PASTE); }
        if self.alternate_screen { self.write(LEAVE_ALT_SCREEN); }
        if not self.cursor_visible { self.write(SHOW_CURSOR); }
        self.started = False;
        self.restored = True;
    }

    def poll_input(timeout_s: float = 0.0) -> str {
        _ = timeout_s;
        if not self.input_queue { return ""; }
        return self.input_queue.pop(0);
    }

    def send_input(data: str) { self.input_queue.append(data); }
    def send_key(key: str) { self.send_input(KEY_SEQUENCES.get(key, key)); }
    def send_paste(text: str) { self.send_input("\x1b[200~" + text + "\x1b[201~"); }

    def resize(columns: int, rows: int) {
        self.columns = max(1, columns);
        self.rows = max(1, rows);
        grid: list[list[TerminalCell]] = [];
        for y in range(self.rows) {
            row: list[TerminalCell] = [];
            for x in range(self.columns) {
                if y < len(self.cells) and x < len(self.cells[y]) { row.append(self.cells[y][x]); }
                else { row.append(self._blank_cell()); }
            }
            grid.append(row);
        }
        self.cells = grid;
        self.cursor_x = min(self.cursor_x, self.columns - 1);
        self.cursor_y = min(self.cursor_y, self.rows - 1);
        self.wrap_pending = False;
    }

    def close_input() { self.eof = True; }

    def viewport() -> list[str] {
        lines: list[str] = [];
        for row in self.cells { lines.append(self._row_text(row)); }
        return lines;
    }

    def viewport_text() -> str { return "\n".join(self.viewport()); }

    def scroll_buffer() -> list[str] {
        out: list[str] = list(self.history);
        out.extend(self.viewport());
        return out;
    }

    def cursor() -> tuple[int, int] { return (self.cursor_x, self.cursor_y); }

    def cell(row: int, col: int) -> dict[str, any] {
        c: TerminalCell = self.cells[row][col];
        return {
            "char": c.data, "fg": c.fg, "bg": c.bg, "bold": c.bold,
            "italics": c.italics, "underscore": c.underscore, "reverse": c.reverse,
        };
    }

    def find(needle: str) -> tuple[int, int] | None {
        rows: list[str] = self.viewport();
        for r in range(len(rows)) {
            col: int = rows[r].find(needle);
            if col >= 0 { return (r, col); }
        }
        return None;
    }

    def line_with(needle: str) -> str {
        for line in self.viewport() { if needle in line { return line; } }
        return "";
    }

    def reset_screen() { self._reset_cells(); self.history = []; }
}
