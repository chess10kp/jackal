impl EmulatedTerminal.init(columns: int = 80, rows: int = 24, scrollback: int = 1000) {
    super.init();
    self.columns = columns;
    self.rows = rows;
    self.screen = VtScreen(columns, rows, scrollback);
    self.input_queue = [];
    self.eof = False;
    self.title = "";
    self.bytes_written = 0;
    self.write_count = 0;
    self.started = False;
    self.restored = True;
    self.alternate_screen = False;
    self.bracketed_paste = False;
    self.cursor_visible = True;
    self.sync_active = False;
}

impl EmulatedTerminal.write(data: str) {
    if not data {
        return;
    }
    self.write_count += 1;
    self.bytes_written += len(data);
    if ENTER_ALT_SCREEN in data {
        self.alternate_screen = True;
    }
    if LEAVE_ALT_SCREEN in data {
        self.alternate_screen = False;
    }
    if ENABLE_BRACKETED_PASTE in data {
        self.bracketed_paste = True;
    }
    if DISABLE_BRACKETED_PASTE in data {
        self.bracketed_paste = False;
    }
    if SYNC_BEGIN in data {
        self.sync_active = True;
    }
    if SYNC_END in data {
        self.sync_active = False;
    }
    self.screen.feed(data);
    self.cursor_visible = not self.screen.cursor_hidden;
    if self.screen.title {
        self.title = self.screen.title;
    }
}

impl EmulatedTerminal.move_cursor(row: int, col: int) {
    self.write(f"\x1b[{row};{col}H");
}

impl EmulatedTerminal.start {
    if self.started {
        return;
    }
    self.write(ENABLE_BRACKETED_PASTE);
    self.write(ENTER_ALT_SCREEN);
    self.write(HIDE_CURSOR);
    self.started = True;
    self.restored = False;
}

impl EmulatedTerminal.stop {
    if self.restored and not self.started {
        return;
    }
    if self.sync_active {
        self.write(SYNC_END);
    }
    if self.bracketed_paste {
        self.write(DISABLE_BRACKETED_PASTE);
    }
    if self.alternate_screen {
        self.write(LEAVE_ALT_SCREEN);
    }
    if not self.cursor_visible {
        self.write(SHOW_CURSOR);
    }
    self.started = False;
    self.restored = True;
}

impl EmulatedTerminal.poll_input(timeout_s: float = 0.0) -> str {
    if not self.input_queue {
        return "";
    }
    return self.input_queue.pop(0);
}

impl EmulatedTerminal.send_input(data: str) {
    self.input_queue.append(data);
}

impl EmulatedTerminal.send_key(key: str) {
    self.send_input(KEY_SEQUENCES.get(key, key));
}

impl EmulatedTerminal.send_paste(text: str) {
    self.send_input("\x1b[200~" + text + "\x1b[201~");
}

impl EmulatedTerminal.resize(columns: int, rows: int) {
    self.columns = columns;
    self.rows = rows;
    self.screen.resize(rows, columns);
}

impl EmulatedTerminal.close_input {
    self.eof = True;
}

impl EmulatedTerminal.viewport -> list[str] {
    return [line.rstrip() for line in self.screen.display()];
}

impl EmulatedTerminal.viewport_text -> str {
    return "\n".join(self.viewport());
}

impl EmulatedTerminal.scroll_buffer -> list[str] {
    out: list[str] = [];
    for row in self.screen.history {
        out.append(self.screen.history_text(row).rstrip());
    }
    return out + self.viewport();
}

impl EmulatedTerminal.cursor -> tuple[int, int] {
    return (self.screen.cursor_x, self.screen.cursor_y);
}

impl EmulatedTerminal.cell(row: int, col: int) -> dict[str, any] {
    c: VtCell = self.screen.buffer[row][col];
    return {
        "char": c.data,
        "fg": c.fg,
        "bg": c.bg,
        "bold": c.bold,
        "italics": c.italics,
        "underscore": c.underscore,
        "reverse": c.reverse,
    };
}

impl EmulatedTerminal.find(needle: str) -> tuple[int, int] | None {
    rows: list[str] = self.viewport();
    for r in range(len(rows)) {
        col: int = rows[r].find(needle);
        if col >= 0 {
            return (r, col);
        }
    }
    return None;
}

impl EmulatedTerminal.line_with(needle: str) -> str {
    for line in self.viewport() {
        if needle in line {
            return line;
        }
    }
    return "";
}

impl EmulatedTerminal.reset_screen {
    self.screen.reset();
}
