"""End-to-end harness: run the real jackal entry as a subprocess against the
offline `mock` provider (agent/llm_transport.jac MockTransport).

Every run gets an isolated project dir, a scripted model (JACKAL_MOCK_SCRIPT),
a request log (JACKAL_MOCK_LOG), and a private JACKAL_AGENT_DIR so no real
credentials, sessions, or network are touched. Suites live next to this file
as e2e/*.test.jac.
"""

import os;
import sys;
import json;
import shutil;
import tempfile;
import subprocess;
import time;
import threading;
import from ui.emulated_terminal { EmulatedTerminal }

glob E2E_TIMEOUT_S: int = 300;


"""app/ directory (this file lives in app/e2e/)."""
def app_dir() -> str {
    env_root: str = os.environ.get("JACKAL_ROOT", "");
    if env_root and os.path.isfile(os.path.join(env_root, "app", "main.jac")) {
        return os.path.join(env_root, "app");
    }
    here: str = os.getcwd();
    for _ in range(4) {
        if os.path.isfile(os.path.join(here, "main.jac")) and os.path.isdir(os.path.join(here, "agent")) {
            return here;
        }
        if os.path.isfile(os.path.join(here, "app", "main.jac")) {
            return os.path.join(here, "app");
        }
        here = os.path.dirname(here);
    }
    raise RuntimeError("e2e: cannot locate app/main.jac (set JACKAL_ROOT)");
}


def jac_bin() -> str {
    got: str | None = os.environ.get("JAC") or shutil.which("jac");
    if not got {
        raise RuntimeError("e2e: jac not on PATH (set JAC)");
    }
    return got;
}


"""Isolated sandbox: a project dir (seeded with `files`, path -> text) and a
private agent dir. Call cleanup() when done."""
obj Sandbox {
    has base_dir: str = "",
        project: str = "",
        agent_dir: str = "",
        script_path: str = "",
        log_path: str = "";

    def write(rel: str, text: str) {
        path: str = os.path.join(self.project, rel);
        os.makedirs(os.path.dirname(path) or self.project, exist_ok=True);
        fh: any = open(path, "w", encoding="utf-8");
        fh.write(text);
        fh.close();
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

    """Script the model: list of mock steps ({"text"}, {"tool_calls"}, {"error"})."""
    def script(steps: list[dict[str, any]]) {
        fh: any = open(self.script_path, "w", encoding="utf-8");
        fh.write(json.dumps(steps));
        fh.close();
    }

    """Model calls recorded by the mock transport, in order."""
    def calls() -> list[dict[str, any]] {
        if not os.path.exists(self.log_path) {
            return [];
        }
        out: list[dict[str, any]] = [];
        fh: any = open(self.log_path, "r", encoding="utf-8");
        for line in fh.read().splitlines() {
            if line.strip() { out.append(json.loads(line)); }
        }
        fh.close();
        return out;
    }

    def cleanup() {
        shutil.rmtree(self.base_dir, ignore_errors=True);
    }

    """A run's describe() plus every model call — the assertion message to
    use whenever a scenario fails."""
    def explain(r: any) -> str {
        return r.describe() + "\n--- model calls ---\n" + json.dumps(self.calls(), indent=1)[:6000];
    }
}


def make_sandbox(files: dict[str, str] | None = None) -> Sandbox {
    base: str = tempfile.mkdtemp(prefix="jackal-e2e-");
    sb = Sandbox(
        base_dir=base,
        project=os.path.join(base, "project"),
        agent_dir=os.path.join(base, "agent"),
        script_path=os.path.join(base, "script.json"),
        log_path=os.path.join(base, "calls.jsonl"),
    );
    os.makedirs(sb.project);
    os.makedirs(sb.agent_dir);
    if files is not None {
        for (rel, text) in files.items() { sb.write(rel, text); }
    }
    return sb;
}


"""Result of one jackal process run."""
obj RunResult {
    has code: int = 0,
        stdout: str = "",
        stderr: str = "";

    """stdout parsed as JSONL (non-JSON lines skipped)."""
    def events() -> list[dict[str, any]] {
        out: list[dict[str, any]] = [];
        for line in self.stdout.splitlines() {
            line = line.strip();
            if not line.startswith("{") { continue; }
            try {
                ev: any = json.loads(line);
                if isinstance(ev, dict) { out.append(ev); }
            } except ValueError {
            }
        }
        return out;
    }

    def event_types() -> list[str] {
        return [str(e.get("type", "")) for e in self.events()];
    }

    def describe() -> str {
        return "exit=" + str(self.code) + "\n--- stdout ---\n" + self.stdout[-4000:]
            + "\n--- stderr ---\n" + self.stderr[-4000:];
    }
}


"""Run `jac run app/main.jac -- ARGS` inside the sandbox project with the mock
model. `stdin_text` is fed to the process (closed afterwards)."""
def run_jackal(
    sb: Sandbox,
    args: list[str],
    stdin_text: str = "",
    env_extra: dict[str, str] | None = None,
    timeout_s: int = E2E_TIMEOUT_S,
) -> RunResult {
    env: dict[str, str] = dict(os.environ);
    for k in ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "DEEPSEEK_API_KEY", "ZAI_API_KEY", "JACKAL_MODE"] {
        env.pop(k, None);
    }
    env["JACKAL_MODEL"] = "mock";
    env["JACKAL_MOCK_SCRIPT"] = sb.script_path;
    env["JACKAL_MOCK_LOG"] = sb.log_path;
    env["JACKAL_AGENT_DIR"] = sb.agent_dir;
    env["NO_COLOR"] = "1";
    if env_extra is not None {
        for (k, v) in env_extra.items() { env[k] = v; }
    }
    cmd: list[str] = [jac_bin(), "run", os.path.join(app_dir(), "main.jac"), "--"] + args;
    try {
        proc: any = subprocess.run(
            cmd, input=stdin_text, capture_output=True, text=True,
            cwd=sb.project, env=env, timeout=timeout_s,
        );
    } except subprocess.TimeoutExpired as e {
        return RunResult(code=-9, stdout=str(e.stdout or ""), stderr="TIMEOUT after " + str(timeout_s) + "s\n" + str(e.stderr or ""));
    }
    return RunResult(code=int(proc.returncode), stdout=str(proc.stdout), stderr=str(proc.stderr));
}


"""JSONL request line for the --json protocol."""
def jsonl(kind: str, text: str = "", extra: dict[str, any] | None = None) -> str {
    req: dict[str, any] = {"type": kind, "text": text};
    if extra is not None {
        for (k, v) in extra.items() { req[k] = v; }
    }
    return json.dumps(req) + "\n";
}


# ============================ PTY / TUI driver ============================

"""Named keys for TuiSession.press."""
glob KEYS: dict[str, str] = {
    "enter": "\r", "esc": "\x1b", "tab": "\t", "backspace": "\x7f",
    "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
    "shift+tab": "\x1b[Z", "ctrl+c": "\x03", "ctrl+d": "\x04",
};


"""A live `jac run tui/shell.jac` under a pseudo-terminal, with its output
replayed into a Screen. Drive it with type_text/press, assert with
wait_for/screen_text, and always close()."""
obj TuiSession {
    has proc: any = None,
        master_fd: int = -1,
        screen: EmulatedTerminal | None = None,
        raw: list[str] = [],
        lock: any = None,
        reader: any = None,
        alive: bool = True;

    def _read_loop() {
        import os;
        import codecs;
        dec: any = codecs.getincrementaldecoder("utf-8")("replace");
        while self.alive {
            try {
                chunk: bytes = os.read(self.master_fd, 65536);
            } except OSError {
                break;
            }
            if not chunk { break; }
            text: str = dec.decode(chunk);
            self.lock.acquire();
            try {
                self.raw.append(text);
                if self.screen is not None { self.screen.write(text); }
            } finally {
                self.lock.release();
            }
        }
        self.alive = False;
    }

    def send(data: str) {
        import os;
        os.write(self.master_fd, data.encode("utf-8"));
    }

    """Type text one character at a time (like a user), then settle briefly."""
    def type_text(text: str, delay_s: float = 0.005) {
        for ch in text {
            self.send(ch);
            time.sleep(delay_s);
        }
    }

    def press(key: str) {
        self.send(KEYS.get(key, key));
    }

    def screen_text() -> str {
        self.lock.acquire();
        try {
            return self.screen.viewport_text() if self.screen is not None else "";
        } finally {
            self.lock.release();
        }
    }

    def raw_output() -> str {
        self.lock.acquire();
        try {
            return "".join(self.raw);
        } finally {
            self.lock.release();
        }
    }

    """Poll until `needle` is on screen; raises AssertionError with the
    screen dump on timeout."""
    def wait_for(needle: str, timeout_s: float = 60.0) -> str {
        deadline: float = time.time() + timeout_s;
        while time.time() < deadline {
            txt: str = self.screen_text();
            if needle in txt { return txt; }
            if not self.alive and self.proc.poll() is not None { break; }
            time.sleep(0.05);
        }
        raise AssertionError(
            "timed out waiting for " + repr(needle) + "\n--- screen ---\n"
            + self.screen_text() + "\n--- exit: " + str(self.proc.poll())
        );
    }

    """Poll until `needle` is NOT on screen; raises AssertionError with the
    screen dump on timeout. For overlay-close assertions: the shell paints
    on its next tick, so an immediate screen_text() after a keypress races
    the previous frame."""
    def wait_gone(needle: str, timeout_s: float = 30.0) -> str {
        deadline: float = time.time() + timeout_s;
        while time.time() < deadline {
            txt: str = self.screen_text();
            if needle not in txt { return txt; }
            if not self.alive and self.proc.poll() is not None { break; }
            time.sleep(0.05);
        }
        raise AssertionError(
            "timed out waiting for " + repr(needle) + " to disappear\n--- screen ---\n"
            + self.screen_text() + "\n--- exit: " + str(self.proc.poll())
        );
    }

    """Wait for the process to exit; returns its code (or None on timeout)."""


    def wait_exit(timeout_s: float = 30.0) -> int | None {
        try {
            return int(self.proc.wait(timeout=timeout_s));
        } except subprocess.TimeoutExpired {
            return None;
        }
    }

    def close() {
        if self.proc is not None and self.proc.poll() is None {
            try {
                os.killpg(int(self.proc.pid), 15);  # SIGTERM
            } except Exception {
            }
            try {
                self.proc.wait(timeout=10);
            } except Exception {
                try { os.killpg(int(self.proc.pid), 9); } except Exception { }  # SIGKILL
            }
        }
        self.alive = False;
        try {
            os.close(self.master_fd);
        } except OSError {
        }
    }
}


"""Launch the native TUI in `sb.project` under a cols x rows PTY with the
mock model. Waits until the first frame is painted."""
def spawn_tui(
    sb: Sandbox,
    cols: int = 100,
    rows: int = 30,
    env_extra: dict[str, str] | None = None,
    boot_timeout_s: float = 240.0,
) -> TuiSession {
    import pty;
    import fcntl;
    import termios;
    import struct;
    (master_fd, slave_fd) = pty.openpty();
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0));
    env: dict[str, str] = dict(os.environ);
    for k in ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "DEEPSEEK_API_KEY", "ZAI_API_KEY", "JACKAL_MODE"] {
        env.pop(k, None);
    }
    env["JACKAL_MODEL"] = "mock";
    env["JACKAL_MOCK_SCRIPT"] = sb.script_path;
    env["JACKAL_MOCK_LOG"] = sb.log_path;
    env["JACKAL_AGENT_DIR"] = sb.agent_dir;
    env["TERM"] = "xterm-256color";
    env["COLUMNS"] = str(cols);
    env["LINES"] = str(rows);
    if env_extra is not None {
        for (k, v) in env_extra.items() { env[k] = v; }
    }
    cmd: list[str] = [jac_bin(), "run", os.path.join(app_dir(), "tui", "shell.jac")];
    proc: any = subprocess.Popen(
        cmd, stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
        cwd=sb.project, env=env, start_new_session=True, close_fds=True,
    );
    os.close(slave_fd);
    sess = TuiSession(
        proc=proc, master_fd=master_fd, screen=EmulatedTerminal(cols, rows),
        raw=[], lock=threading.Lock(), alive=True,
    );
    sess.reader = threading.Thread(target=sess._read_loop, daemon=True);
    sess.reader.start();
    # First frame: the status line's ready phase. (Compiler diagnostics may
    # be printed before the TUI takes over the screen on a cold cache.)
    sess.wait_for("\u25cf ready", boot_timeout_s);
    return sess;
}


"""Absolute path of an e2e fixture file."""
def fixture_path(name: str) -> str {
    return os.path.join(app_dir(), "e2e", "fixtures", name);
}


"""Write the project config as .jackal/config.json (directory form, so
sessions and tasks can live alongside it) — e.g. MCP servers."""
def write_project_config(sb: Sandbox, cfg: dict[str, any]) {
    sb.write(".jackal/config.json", json.dumps(cfg));
}
