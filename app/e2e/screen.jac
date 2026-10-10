"""Minimal ANSI screen emulator for PTY-driven TUI e2e tests.

Covers what a differential renderer emits: CSI cursor moves (H f A B C D G
d E F), erase (K J), CR/LF/BS/TAB, and skips SGR, private modes, and OSC.
Partial escape sequences split across reads are buffered. Styles are
dropped — assertions are on text.
"""

import unicodedata;


obj Screen {
    has columns: int = 80,
        rows: int = 24,
        grid: list[list[str]] = [],
        row: int = 0,
        col: int = 0,
        pending: str = "";

    def postinit() {
        self.clear();
    }

    def clear() {
        self.grid = [[" " for _c in range(self.columns)] for _r in range(self.rows)];
        self.row = 0;
        self.col = 0;
    }

    def _clamp() {
        self.row = max(0, min(self.rows - 1, self.row));
        self.col = max(0, min(self.columns - 1, self.col));
    }

    def _linefeed() {
        if self.row < self.rows - 1 {
            self.row += 1;
            return;
        }
        self.grid.pop(0);
        self.grid.append([" " for _c in range(self.columns)]);
    }

    def _put(ch: str) {
        if self.col >= self.columns {
            self.col = 0;
            self._linefeed();
        }
        self.grid[self.row][self.col] = ch;
        self.col += 1;
        if unicodedata.east_asian_width(ch) in ("W", "F") and self.col < self.columns {
            self.grid[self.row][self.col] = "";
            self.col += 1;
        }
    }

    def _erase_line(mode: int) {
        line: list[str] = self.grid[self.row];
        if mode == 0 {
            for c in range(self.col, self.columns) { line[c] = " "; }
        } elif mode == 1 {
            for c in range(0, min(self.col + 1, self.columns)) { line[c] = " "; }
        } else {
            for c in range(self.columns) { line[c] = " "; }
        }
    }

    def _erase_display(mode: int) {
        if mode == 2 or mode == 3 {
            saved_row: int = self.row;
            saved_col: int = self.col;
            self.clear();
            self.row = saved_row;
            self.col = saved_col;
            return;
        }
        if mode == 0 {
            self._erase_line(0);
            for r in range(self.row + 1, self.rows) {
                self.grid[r] = [" " for _c in range(self.columns)];
            }
        } else {
            self._erase_line(1);
            for r in range(0, self.row) {
                self.grid[r] = [" " for _c in range(self.columns)];
            }
        }
    }

    def _csi(params: str, final: str) {
        if params.startswith("?") or params.startswith(">") or params.startswith("<") or params.startswith("=") {
            return;
        }
        nums: list[int] = [];
        for p in params.split(";") {
            nums.append(int(p) if p.isdigit() else 0);
        }
        n: int = nums[0] if nums and nums[0] > 0 else 1;
        if final in ("H", "f") {
            r: int = nums[0] if len(nums) > 0 and nums[0] > 0 else 1;
            c: int = nums[1] if len(nums) > 1 and nums[1] > 0 else 1;
            self.row = r - 1;
            self.col = c - 1;
        } elif final == "A" { self.row -= n; }
        elif final == "B" { self.row += n; }
        elif final == "C" { self.col += n; }
        elif final == "D" { self.col -= n; }
        elif final == "E" { self.row += n; self.col = 0; }
        elif final == "F" { self.row -= n; self.col = 0; }
        elif final == "G" { self.col = n - 1; }
        elif final == "d" { self.row = n - 1; }
        elif final == "K" { self._erase_line(nums[0] if nums else 0); }
        elif final == "J" { self._erase_display(nums[0] if nums else 0); }
        self._clamp();
    }

    """Apply terminal output; incomplete trailing escapes wait for more."""
    def feed(data: str) {
        buf: str = self.pending + data;
        self.pending = "";
        i: int = 0;
        n: int = len(buf);
        while i < n {
            ch: str = buf[i];
            if ch == "\x1b" {
                if i + 1 >= n { self.pending = buf[i:]; return; }
                nxt: str = buf[i + 1];
                if nxt == "[" {
                    j: int = i + 2;
                    while j < n and not (64 <= ord(buf[j]) <= 126) { j += 1; }
                    if j >= n { self.pending = buf[i:]; return; }
                    self._csi(buf[i + 2:j], buf[j]);
                    i = j + 1;
                    continue;
                }
                if nxt == "]" {
                    # OSC: terminated by BEL or ESC \.
                    j = i + 2;
                    end: int = -1;
                    while j < n {
                        if buf[j] == "\x07" { end = j + 1; break; }
                        if buf[j] == "\x1b" and j + 1 < n and buf[j + 1] == "\\" { end = j + 2; break; }
                        j += 1;
                    }
                    if end < 0 { self.pending = buf[i:]; return; }
                    i = end;
                    continue;
                }
                # Two-byte escapes (ESC 7/8/=/>/M ...): ignore.
                i += 2;
                continue;
            }
            if ch == "\r" { self.col = 0; }
            elif ch == "\n" { self._linefeed(); }
            elif ch == "\b" { self.col = max(0, self.col - 1); }
            elif ch == "\t" { self.col = min(self.columns - 1, (self.col // 8 + 1) * 8); }
            elif ord(ch) >= 32 and ch != "\x7f" { self._put(ch); }
            i += 1;
        }
    }

    def lines() -> list[str] {
        return ["".join(r).rstrip() for r in self.grid];
    }

    def text() -> str {
        return "\n".join(self.lines());
    }
}
