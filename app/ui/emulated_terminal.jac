"""Terminal backed by a real VT emulator (native ui/vt_screen.jac; was pyte) — the Jac counterpart of Pi's
xterm-headless VirtualTerminal (reference/pi/packages/tui/test/virtual-terminal.ts).

Everything the app writes is interpreted the way a real terminal would:
cursor addressing, erase, scroll regions, wrapping, wide characters, SGR
styles, cursor visibility. Tests read back exactly what a user would see
(viewport, scrollback, cursor, per-cell style) and inject keystrokes and
resizes. Implements the same surface the live shell uses on ProcessTerminal
(start/stop/write/size/poll_input/eof), so the real TUI runs against it
in-process.
"""

import from ui.vt_screen { VtScreen, VtCell }
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


obj EmulatedTerminal(Terminal) {
    has screen: VtScreen = VtScreen(),
        input_queue: list[str] = [],
        title: str = "",
        bytes_written: int = 0,
        write_count: int = 0;

    def init(columns: int = 80, rows: int = 24, scrollback: int = 1000) {
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

    # ---------------------------------------------------- Terminal surface

    def write(data: str) -> None {
        if not data {
            return;
        }
        self.write_count += 1;
        self.bytes_written += len(data);
        # Mode flags pyte does not model (alt screen, paste, sync) are
        # tracked from the byte stream so restore can be asserted.
        if ENTER_ALT_SCREEN in data { self.alternate_screen = True; }
        if LEAVE_ALT_SCREEN in data { self.alternate_screen = False; }
        if ENABLE_BRACKETED_PASTE in data { self.bracketed_paste = True; }
        if DISABLE_BRACKETED_PASTE in data { self.bracketed_paste = False; }
        if SYNC_BEGIN in data { self.sync_active = True; }
        if SYNC_END in data { self.sync_active = False; }
        self.screen.feed(data);
        self.cursor_visible = not self.screen.cursor_hidden;
        if self.screen.title { self.title = self.screen.title; }
    }

    def move_cursor(row: int, col: int) -> None {
        self.write(f"\x1b[{row};{col}H");
    }

    def start -> None {
        if self.started {
            return;
        }
        self.write(ENABLE_BRACKETED_PASTE);
        self.write(ENTER_ALT_SCREEN);
        self.write(HIDE_CURSOR);
        self.started = True;
        self.restored = False;
    }

    def stop -> None {
        if self.restored and not self.started {
            return;
        }
        if self.sync_active { self.write(SYNC_END); }
        if self.bracketed_paste { self.write(DISABLE_BRACKETED_PASTE); }
        if self.alternate_screen { self.write(LEAVE_ALT_SCREEN); }
        if not self.cursor_visible { self.write(SHOW_CURSOR); }
        self.started = False;
        self.restored = True;
    }

    """Non-blocking: next queued input chunk, or "" (the host loop polls)."""
    def poll_input(timeout_s: float = 0.0) -> str {
        if not self.input_queue {
            return "";
        }
        return self.input_queue.pop(0);
    }

    # ------------------------------------------------------- test drivers

    """Queue raw input bytes as if typed (delivered on the next poll)."""
    def send_input(data: str) {
        self.input_queue.append(data);
    }

    """Queue a named key (see KEY_SEQUENCES); unknown names are sent raw."""
    def send_key(key: str) {
        self.send_input(KEY_SEQUENCES.get(key, key));
    }

    """Queue a bracketed paste."""
    def send_paste(text: str) {
        self.send_input("\x1b[200~" + text + "\x1b[201~");
    }

    """Resize the emulated screen; the host notices via size()."""
    def resize(columns: int, rows: int) {
        self.columns = columns;
        self.rows = rows;
        self.screen.resize(rows, columns);
    }

    """Simulate stdin closing (ctrl+d on an empty tty / pipe EOF)."""
    def close_input  {
        self.eof = True;
    }

    # ---------------------------------------------------------- read-back

    """Visible rows, trailing spaces trimmed (Pi: getViewport)."""
    def viewport -> list[str] {
        return [line.rstrip() for line in self.screen.display()];
    }

    def viewport_text -> str {
        return "\n".join(self.viewport());
    }

    """Scrollback above the viewport plus the viewport (Pi: getScrollBuffer)."""
    def scroll_buffer -> list[str] {
        out: list[str] = [];
        for row in self.screen.history {
            out.append(self.screen.history_text(row).rstrip());
        }
        return out + self.viewport();
    }

    """(x, y) zero-based cursor position (Pi: getCursorPosition)."""
    def cursor -> tuple[int, int] {
        return (self.screen.cursor_x, self.screen.cursor_y);
    }

    """Style of one cell: char, fg, bg, bold, italics, underscore, reverse."""
    def cell(row: int, col: int) -> dict[str, any] {
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

    """First (row, col) where `needle` appears in the viewport, or None."""
    def find(needle: str) -> tuple[int, int] | None {
        rows: list[str] = self.viewport();
        for r in range(len(rows)) {
            col: int = rows[r].find(needle);
            if col >= 0 { return (r, col); }
        }
        return None;
    }

    """Viewport row containing `needle`, or ""."""
    def line_with(needle: str) -> str {
        for line in self.viewport() {
            if needle in line { return line; }
        }
        return "";
    }

    """Clear screen state (keeps size and flags)."""
    def reset_screen  {
        self.screen.reset();
    }
}
