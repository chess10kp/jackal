impl _hex2(v: int) -> str {
    digits: str = "0123456789abcdef";
    return digits[(v // 16) % 16] + digits[v % 16];
}

impl _color256(n: int) -> str {
    if n < 16 {
        return _BASE16_HEX[n];
    }
    if n < 232 {
        k: int = n - 16;
        steps: list[int] = [0, 95, 135, 175, 215, 255];
        return _hex2(steps[k // 36]) + _hex2(steps[(k // 6) % 6]) + _hex2(steps[k % 6]);
    }
    g: int = 8 + (n - 232) * 10;
    return _hex2(g) + _hex2(g) + _hex2(g);
}

impl VtScreen.init(columns: int = 80, rows: int = 24, history_max: int = 1000) {
    self.columns = columns;
    self.rows = rows;
    self.history_max = history_max;
    self.history = [];
    self.reset();
}

impl VtScreen._blank -> VtCell {
    a: VtCell = self.attrs;
    return VtCell(
        data=" ", fg=a.fg, bg=a.bg, bold=False, italics=False, underscore=False, reverse=a.reverse
    );
}

impl VtScreen._blank_line -> list[VtCell] {
    line: list[VtCell] = [];
    for _ in range(self.columns) {
        line.append(self._blank());
    }
    return line;
}

impl VtScreen._clamp_cursor {
    if self.cursor_x < 0 {
        self.cursor_x = 0;
    }
    if self.cursor_x > self.columns - 1 {
        self.cursor_x = self.columns - 1;
    }
    if self.cursor_y < 0 {
        self.cursor_y = 0;
    }
    if self.cursor_y > self.rows - 1 {
        self.cursor_y = self.rows - 1;
    }
}

impl VtScreen.reset {
    self.buffer = [];
    self.attrs = VtCell();
    for _ in range(self.rows) {
        self.buffer.append(self._blank_line());
    }
    self.cursor_x = 0;
    self.cursor_y = 0;
    self.cursor_hidden = False;
    self.scroll_top = 0;
    self.scroll_bottom = self.rows - 1;
    self.saved_x = 0;
    self.saved_y = 0;
    self.saved_attrs = VtCell();
    self.state = "ground";
    self.seq = "";
    self.last_x = -1;
    self.last_y = -1;
}

impl VtScreen.resize(rows: int, columns: int) {
    while len(self.buffer) > rows {
        self._push_history(self.buffer.pop(0));
        self.cursor_y -= 1;
    }
    self.columns = columns;
    while len(self.buffer) < rows {
        self.buffer.append(self._blank_line());
    }
    for line in self.buffer {
        while len(line) > columns {
            line.pop();
        }
        while len(line) < columns {
            line.append(VtCell());
        }
    }
    self.rows = rows;
    self.scroll_top = 0;
    self.scroll_bottom = rows - 1;
    self._clamp_cursor();
}

impl VtScreen._push_history(line: list[VtCell]) {
    if self.history_max <= 0 {
        return;
    }
    self.history.append(line);
    while len(self.history) > self.history_max {
        self.history.pop(0);
    }
}

impl VtScreen.display -> list[str] {
    out: list[str] = [];
    for line in self.buffer {
        parts: list[str] = [];
        for c in line {
            parts.append(c.data);
        }
        out.append("".join(parts));
    }
    return out;
}

impl VtScreen.history_text(line: list[VtCell]) -> str {
    parts: list[str] = [];
    for x in range(self.columns) {
        parts.append(line[x].data if x < len(line) else " ");
    }
    return "".join(parts);
}

impl VtScreen._scroll_up(n: int) {
    for _ in range(n) {
        line: list[VtCell] = self.buffer.pop(self.scroll_top);
        if self.scroll_top == 0 {
            self._push_history(line);
        }
        self.buffer.insert(self.scroll_bottom, self._blank_line());
    }
}

impl VtScreen._scroll_down(n: int) {
    for _ in range(n) {
        self.buffer.pop(self.scroll_bottom);
        self.buffer.insert(self.scroll_top, self._blank_line());
    }
}

impl VtScreen.index {
    if self.cursor_y == self.scroll_bottom {
        self._scroll_up(1);
    } elif self.cursor_y < self.rows - 1 {
        self.cursor_y += 1;
    }
}

impl VtScreen.reverse_index {
    if self.cursor_y == self.scroll_top {
        self._scroll_down(1);
    } elif self.cursor_y > 0 {
        self.cursor_y -= 1;
    }
}

impl VtScreen._draw(ch: str) {
    w: int = grapheme_width(ch);
    if w <= 0 {
        if self.last_y >= 0
            and self.last_y < self.rows
            and self.last_x >= 0
            and self.last_x < self.columns
        {
            cell: VtCell = self.buffer[self.last_y][self.last_x];
            cell.data = cell.data + ch;
        }
        return;
    }
    if self.cursor_x + w > self.columns {
        self.cursor_x = 0;
        self.index();
    }
    a: VtCell = self.attrs;
    line: list[VtCell] = self.buffer[self.cursor_y];
    line[self.cursor_x] = VtCell(
        data=ch,
        fg=a.fg,
        bg=a.bg,
        bold=a.bold,
        italics=a.italics,
        underscore=a.underscore,
        reverse=a.reverse,
    );
    self.last_x = self.cursor_x;
    self.last_y = self.cursor_y;
    if w == 2 and self.cursor_x + 1 < self.columns {
        line[self.cursor_x + 1] = VtCell(
            data="",
            fg=a.fg,
            bg=a.bg,
            bold=a.bold,
            italics=a.italics,
            underscore=a.underscore,
            reverse=a.reverse,
        );
    }
    self.cursor_x = self.cursor_x + w;
}

impl VtScreen._erase_cells(y: int, x0: int, x1: int) {
    line: list[VtCell] = self.buffer[y];
    for x in range(max(0, x0), min(self.columns, x1)) {
        line[x] = self._blank();
    }
}

impl VtScreen._erase_display(how: int) {
    if how == 0 {
        self._erase_cells(self.cursor_y, self.cursor_x, self.columns);
        for y in range(self.cursor_y + 1, self.rows) {
            self.buffer[y] = self._blank_line();
        }
    } elif how == 1 {
        for y in range(0, self.cursor_y) {
            self.buffer[y] = self._blank_line();
        }
        self._erase_cells(self.cursor_y, 0, self.cursor_x + 1);
    } elif how == 2 or how == 3 {
        for y in range(self.rows) {
            self.buffer[y] = self._blank_line();
        }
        if how == 3 {
            self.history = [];
        }
    }
}

impl VtScreen._erase_line(how: int) {
    if how == 0 {
        self._erase_cells(self.cursor_y, self.cursor_x, self.columns);
    } elif how == 1 {
        self._erase_cells(self.cursor_y, 0, self.cursor_x + 1);
    } else {
        self._erase_cells(self.cursor_y, 0, self.columns);
    }
}

impl VtScreen._insert_lines(n: int) {
    if self.cursor_y < self.scroll_top or self.cursor_y > self.scroll_bottom {
        return;
    }
    for _ in range(n) {
        self.buffer.pop(self.scroll_bottom);
        self.buffer.insert(self.cursor_y, self._blank_line());
    }
    self.cursor_x = 0;
}

impl VtScreen._delete_lines(n: int) {
    if self.cursor_y < self.scroll_top or self.cursor_y > self.scroll_bottom {
        return;
    }
    for _ in range(n) {
        self.buffer.pop(self.cursor_y);
        self.buffer.insert(self.scroll_bottom, self._blank_line());
    }
    self.cursor_x = 0;
}

impl VtScreen._insert_chars(n: int) {
    line: list[VtCell] = self.buffer[self.cursor_y];
    x: int = min(self.cursor_x, self.columns - 1);
    for _ in range(n) {
        line.insert(x, self._blank());
        line.pop();
    }
}

impl VtScreen._delete_chars(n: int) {
    line: list[VtCell] = self.buffer[self.cursor_y];
    x: int = min(self.cursor_x, self.columns - 1);
    for _ in range(n) {
        line.pop(x);
        line.append(self._blank());
    }
}

impl VtScreen._sgr(params: list[int]) {
    if not params {
        params = [0];
    }
    a: VtCell = self.attrs;
    i: int = 0;
    while i < len(params) {
        p: int = params[i];
        if p == 0 {
            self.attrs = VtCell();
            a = self.attrs;
        } elif p == 1 {
            a.bold = True;
        } elif p == 3 {
            a.italics = True;
        } elif p == 4 {
            a.underscore = True;
        } elif p == 7 {
            a.reverse = True;
        } elif p == 22 {
            a.bold = False;
        } elif p == 23 {
            a.italics = False;
        } elif p == 24 {
            a.underscore = False;
        } elif p == 27 {
            a.reverse = False;
        } elif p >= 30 and p <= 37 {
            a.fg = _FG_NAMES[p - 30];
        } elif p == 39 {
            a.fg = "default";
        } elif p >= 40 and p <= 47 {
            a.bg = _FG_NAMES[p - 40];
        } elif p == 49 {
            a.bg = "default";
        } elif p >= 90 and p <= 97 {
            a.fg = _BRIGHT_NAMES[p - 90];
        } elif p >= 100 and p <= 107 {
            a.bg = _BRIGHT_NAMES[p - 100];
        } elif (p == 38 or p == 48) and i + 1 < len(params) {
            color: str = "";
            if params[i + 1] == 5 and i + 2 < len(params) {
                color = _color256(params[i + 2] % 256);
                i += 2;
            } elif params[i + 1] == 2 and i + 4 < len(params) {
                color = _hex2(params[i + 2] % 256)
                    + _hex2(params[i + 3] % 256)
                    + _hex2(params[i + 4] % 256);
                i += 4;
            } else {
                i += 1;
            }
            if color {
                if p == 38 {
                    a.fg = color;
                } else {
                    a.bg = color;
                }
            }
        }
        i += 1;
    }
}

impl VtScreen._csi(body: str) {
    final: str = body[-1];
    raw: str = body[:-1];
    private: bool = False;
    if raw and (raw[0] == "?" or raw[0] == ">" or raw[0] == "<" or raw[0] == "=") {
        private = raw[0] == "?";
        raw = raw[1:];
    }
    params: list[int] = [];
    if raw {
        for part in raw.replace(":", ";").split(";") {
            digits: str = "";
            for c in part {
                if c >= "0" and c <= "9" {
                    digits += c;
                }
            }
            params.append(int(digits) if digits else 0);
        }
    }
    n: int = params[0] if params and params[0] > 0 else 1;
    if private {
        if final == "h" or final == "l" {
            for p in params {
                if p == 25 {
                    self.cursor_hidden = final == "l";
                }
            }
        }
        return;
    }
    if final == "A" {
        floor_y: int = self.scroll_top if self.cursor_y >= self.scroll_top else 0;
        self.cursor_y = max(floor_y, self.cursor_y - n);
    } elif final == "B" or final == "e" {
        ceil_y: int = self.scroll_bottom if self.cursor_y <= self.scroll_bottom else self.rows - 1;
        self.cursor_y = min(ceil_y, self.cursor_y + n);
    } elif final == "C" or final == "a" {
        self.cursor_x = min(self.columns - 1, self.cursor_x + n);
    } elif final == "D" {
        self.cursor_x = max(0, min(self.cursor_x, self.columns - 1) - n);
    } elif final == "E" {
        self.cursor_x = 0;
        self.cursor_y = min(self.rows - 1, self.cursor_y + n);
    } elif final == "F" {
        self.cursor_x = 0;
        self.cursor_y = max(0, self.cursor_y - n);
    } elif final == "G" or final == "`" {
        self.cursor_x = n - 1;
        self._clamp_cursor();
    } elif final == "d" {
        self.cursor_y = n - 1;
        self._clamp_cursor();
    } elif final == "H" or final == "f" {
        row: int = params[0] if len(params) > 0 and params[0] > 0 else 1;
        col: int = params[1] if len(params) > 1 and params[1] > 0 else 1;
        self.cursor_y = row - 1;
        self.cursor_x = col - 1;
        self._clamp_cursor();
    } elif final == "J" {
        self._erase_display(params[0] if params else 0);
    } elif final == "K" {
        self._erase_line(params[0] if params else 0);
    } elif final == "L" {
        self._insert_lines(n);
    } elif final == "M" {
        self._delete_lines(n);
    } elif final == "@" {
        self._insert_chars(n);
    } elif final == "P" {
        self._delete_chars(n);
    } elif final == "X" {
        x0: int = min(self.cursor_x, self.columns - 1);
        self._erase_cells(self.cursor_y, x0, x0 + n);
    } elif final == "S" {
        self._scroll_up(n);
    } elif final == "T" {
        self._scroll_down(n);
    } elif final == "m" {
        self._sgr(params);
    } elif final == "r" {
        top: int = params[0] if len(params) > 0 and params[0] > 0 else 1;
        bottom: int = params[1] if len(params) > 1 and params[1] > 0 else self.rows;
        if bottom > self.rows {
            bottom = self.rows;
        }
        if bottom - top >= 1 {
            self.scroll_top = top - 1;
            self.scroll_bottom = bottom - 1;
            self.cursor_x = 0;
            self.cursor_y = 0;
        }
    } elif final == "s" {
        self._save_cursor();
    } elif final == "u" {
        self._restore_cursor();
    }
}

impl VtScreen._save_cursor {
    self.saved_x = self.cursor_x;
    self.saved_y = self.cursor_y;
    a: VtCell = self.attrs;
    self.saved_attrs = VtCell(
        data=" ",
        fg=a.fg,
        bg=a.bg,
        bold=a.bold,
        italics=a.italics,
        underscore=a.underscore,
        reverse=a.reverse,
    );
}

impl VtScreen._restore_cursor {
    self.cursor_x = self.saved_x;
    self.cursor_y = self.saved_y;
    s: VtCell = self.saved_attrs;
    self.attrs = VtCell(
        data=" ",
        fg=s.fg,
        bg=s.bg,
        bold=s.bold,
        italics=s.italics,
        underscore=s.underscore,
        reverse=s.reverse,
    );
    self._clamp_cursor();
}

impl VtScreen._osc(body: str) {
    sep: int = body.find(";");
    if sep < 0 {
        return;
    }
    kind: str = body[:sep];
    if kind == "0" or kind == "2" {
        self.title = body[sep + 1:];
    }
}

impl VtScreen.feed(data: str) {
    for ch in data {
        st: str = self.state;
        if st == "ground" {
            if ch == "\x1b" {
                self.state = "esc";
            } elif ch == "\r" {
                self.cursor_x = 0;
            } elif ch == "\n" or ch == "\x0b" or ch == "\x0c" {
                self.index();
            } elif ch == "\x08" {
                if self.cursor_x >= self.columns {
                    self.cursor_x = self.columns - 1;
                }
                self.cursor_x = max(0, self.cursor_x - 1);
            } elif ch == "\t" {
                nxt: int = (self.cursor_x // 8 + 1) * 8;
                self.cursor_x = min(self.columns - 1, nxt);
            } elif ch == "\x07" or ch == "\x00" or ch == "\x0e" or ch == "\x0f" {
                continue;
            } elif ord(ch) < 32 or ord(ch) == 127 {
                continue;
            } else {
                self._draw(ch);
            }
        } elif st == "esc" {
            if ch == "[" {
                self.state = "csi";
                self.seq = "";
            } elif ch == "]" {
                self.state = "osc";
                self.seq = "";
            } elif ch == "(" or ch == ")" or ch == "*" or ch == "+" or ch == "#" or ch == "%" {
                self.state = "charset";
            } elif ch == "P" or ch == "_" or ch == "^" or ch == "X" {
                self.state = "string";
            } else {
                self.state = "ground";
                if ch == "7" {
                    self._save_cursor();
                } elif ch == "8" {
                    self._restore_cursor();
                } elif ch == "D" {
                    self.index();
                } elif ch == "E" {
                    self.cursor_x = 0;
                    self.index();
                } elif ch == "M" {
                    self.reverse_index();
                } elif ch == "c" {
                    self.reset();
                }
            }
        } elif st == "csi" {
            o: int = ord(ch);
            if o >= 64 and o <= 126 {
                self.state = "ground";
                self._csi(self.seq + ch);
                self.seq = "";
            } elif ch == "\x1b" {
                self.state = "esc";
                self.seq = "";
            } else {
                self.seq += ch;
            }
        } elif st == "osc" {
            if ch == "\x07" {
                self.state = "ground";
                self._osc(self.seq);
                self.seq = "";
            } elif ch == "\x1b" {
                self.state = "osc_esc";
            } else {
                self.seq += ch;
            }
        } elif st == "osc_esc" {
            self.state = "ground";
            self._osc(self.seq);
            self.seq = "";
            if ch != "\\" {
                self.state = "esc";
                if ch == "[" {
                    self.state = "csi";
                }
            }
        } elif st == "string" {
            if ch == "\x07" {
                self.state = "ground";
            } elif ch == "\x1b" {
                self.state = "osc_esc_drop";
            }
        } elif st == "osc_esc_drop" {
            self.state = "ground";
        } elif st == "charset" {
            self.state = "ground";
        }
    }
}
