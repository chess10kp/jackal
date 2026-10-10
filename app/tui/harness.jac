"""In-process TUI test harness: the real LiveShell rendering into an
EmulatedTerminal (pyte), with the offline mock model.

Mirrors how Pi tests its TUI against xterm-headless: no PTY, no subprocess,
no sleeps-and-hope — the test owns the host loop and steps it, so every
assertion sees exactly the frame a user would.

    h = open_tui(files={"a.txt": "x"}, script=[{"text": "hi"}]);
    try {
        h.type_text("hello");
        h.press("enter");
        h.wait_for("hi");
        assert h.term.find("hi") is not None;
    } finally {
        h.close();
    }
"""

import os;
import json;
import time;
import shutil;
import tempfile;
import from ui.emulated_terminal { EmulatedTerminal }
import from tui.state { LiveShell }
import from tui.shell { boot_tui, tui_step, shutdown_tui }
import from agent.session { restore_model, clear_history, set_mode }

glob _HARNESS_ENV_KEYS: list[str] = [
    "JACKAL_MODEL", "JACKAL_MOCK_SCRIPT", "JACKAL_MOCK_LOG", "JACKAL_AGENT_DIR",
    "JACKAL_MODE", "OPENROUTER_API_KEY", "OPENAI_API_KEY", "DEEPSEEK_API_KEY", "ZAI_API_KEY",
];


obj TuiHarness {
    has app: LiveShell,
        term: EmulatedTerminal,
        base_dir: str = "",
        project: str = "",
        log_path: str = "",
        script_path: str = "",
        saved_cwd: str = "",
        saved_env: dict[str, any] = {},
        closed: bool = False;

    """Run `n` host-loop iterations without blocking on input."""
    def step(n: int = 1) {
        for _ in range(n) {
            tui_step(self.app, 0.0);
        }
    }

    """Type text one character per loop tick, like a user."""
    def type_text(text: str) {
        for ch in text {
            self.term.send_input(ch);
            self.step(1);
        }
    }

    """Press a named key (ui/emulated_terminal.jac KEY_SEQUENCES) and tick.
    A lone ESC is flushed by the normalizer on the following idle tick."""
    def press(key: str) {
        self.term.send_key(key);
        self.step(2);
    }

    def paste(text: str) {
        self.term.send_paste(text);
        self.step(1);
    }

    def resize(columns: int, rows: int) {
        self.term.resize(columns, rows);
        self.step(2);
    }

    def screen() -> str {
        return self.term.viewport_text();
    }

    """Step until `needle` is visible; on timeout fail with the screen."""
    def wait_for(needle: str, timeout_s: float = 30.0) -> str {
        deadline: float = time.time() + timeout_s;
        while time.time() < deadline {
            self.step(1);
            txt: str = self.screen();
            if needle in txt { return txt; }
            time.sleep(0.01);
        }
        raise AssertionError("timed out waiting for " + repr(needle) + "\n" + self.dump());
    }

    """Step until `needle` is gone from the screen."""
    def wait_gone(needle: str, timeout_s: float = 30.0) {
        deadline: float = time.time() + timeout_s;
        while time.time() < deadline {
            self.step(1);
            if needle not in self.screen() { return; }
            time.sleep(0.01);
        }
        raise AssertionError("still showing " + repr(needle) + "\n" + self.dump());
    }

    """Step until the agent turn finishes (phase back to ready)."""
    def wait_idle(timeout_s: float = 30.0) {
        deadline: float = time.time() + timeout_s;
        while time.time() < deadline {
            self.step(1);
            if self.app.phase == "ready" and self.app.worker is None { return; }
            time.sleep(0.01);
        }
        raise AssertionError("turn did not settle (phase=" + self.app.phase + ")\n" + self.dump());
    }

    """Model calls recorded by the mock transport."""
    def calls() -> list[dict[str, any]] {
        if not os.path.exists(self.log_path) { return []; }
        out: list[dict[str, any]] = [];
        fh: any = open(self.log_path, "r", encoding="utf-8");
        for line in fh.read().splitlines() {
            if line.strip() { out.append(json.loads(line)); }
        }
        fh.close();
        return out;
    }

    def read(rel: str) -> str {
        fh: any = open(os.path.join(self.project, rel), "r", encoding="utf-8");
        txt: str = fh.read();
        fh.close();
        return txt;
    }

    def exists(rel: str) -> bool {
        return os.path.exists(os.path.join(self.project, rel));
    }

    """Screen + cursor + phase, for assertion messages."""
    def dump() -> str {
        (x, y) = self.term.cursor();
        border: str = "+" + "-" * self.term.columns + "+";
        rows: list[str] = [border];
        for line in self.term.viewport() {
            rows.append("|" + line.ljust(self.term.columns) + "|");
        }
        rows.append(border);
        return (
            "\n".join(rows) + "\ncursor=(" + str(x) + "," + str(y) + ") phase="
            + self.app.phase + " running=" + str(self.app.running)
            + "\nmodel calls: " + json.dumps(self.calls())[:2000]
        );
    }

    def close() {
        if self.closed { return; }
        self.closed = True;
        try {
            self.app.running = False;
            shutdown_tui(self.app);
        } finally {
            os.chdir(self.saved_cwd);
            for (k, v) in self.saved_env.items() {
                if v is None { os.environ.pop(k, None); }
                else { os.environ[k] = str(v); }
            }
            shutil.rmtree(self.base_dir, ignore_errors=True);
        }
    }
}


"""Boot the real TUI on an emulated `columns` x `rows` terminal inside a
throwaway project (seeded with `files`), driven by the mock model `script`."""
def open_tui(
    columns: int = 100,
    rows: int = 30,
    files: dict[str, str] | None = None,
    script: list[dict[str, any]] | None = None,
    mode: str = "normal",
) -> TuiHarness {
    base: str = tempfile.mkdtemp(prefix="jackal-tui-");
    project: str = os.path.join(base, "project");
    agent_dir: str = os.path.join(base, "agent");
    os.makedirs(project);
    os.makedirs(agent_dir);
    if files is not None {
        for (rel, text) in files.items() {
            path: str = os.path.join(project, rel);
            os.makedirs(os.path.dirname(path), exist_ok=True);
            fh: any = open(path, "w", encoding="utf-8");
            fh.write(text);
            fh.close();
        }
    }
    script_path: str = os.path.join(base, "script.json");
    sf: any = open(script_path, "w", encoding="utf-8");
    sf.write(json.dumps(script if script is not None else []));
    sf.close();
    saved_env: dict[str, any] = {};
    for k in _HARNESS_ENV_KEYS { saved_env[k] = os.environ.get(k); }
    for k in _HARNESS_ENV_KEYS { os.environ.pop(k, None); }
    os.environ["JACKAL_MODEL"] = "mock";
    os.environ["JACKAL_MOCK_SCRIPT"] = script_path;
    os.environ["JACKAL_MOCK_LOG"] = os.path.join(base, "calls.jsonl");
    os.environ["JACKAL_AGENT_DIR"] = agent_dir;
    saved_cwd: str = os.getcwd();
    os.chdir(project);
    term = EmulatedTerminal(columns, rows);
    clear_history();
    restore_model("mock");
    app = boot_tui(term);
    set_mode(mode);
    app.mode = mode;
    h = TuiHarness(
        app=app, term=term, base_dir=base, project=project,
        log_path=os.path.join(base, "calls.jsonl"), script_path=script_path,
        saved_cwd=saved_cwd, saved_env=saved_env,
    );
    h.step(2);
    return h;
}
