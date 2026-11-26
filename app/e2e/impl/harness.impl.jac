impl app_dir -> str {
    env_root: str = os.environ.get("JACKAL_ROOT", "");
    if env_root and os.path.isfile(os.path.join(env_root, "app", "main.jac")) {
        return os.path.join(env_root, "app");
    }
    cur_dir: str = os.getcwd();
    for _ in range(4) {
        if os.path.isfile(os.path.join(cur_dir, "main.jac"))
            and os.path.isdir(os.path.join(cur_dir, "agent"))
        {
            return cur_dir;
        }
        if os.path.isfile(os.path.join(cur_dir, "app", "main.jac")) {
            return os.path.join(cur_dir, "app");
        }
        cur_dir = os.path.dirname(cur_dir);
    }
    raise RuntimeError("e2e: cannot locate app/main.jac (set JACKAL_ROOT)");
}

impl jac_bin -> str {
    got: str | None = os.environ.get("JAC") or shutil.which("neojac") or shutil.which("jac");
    if not got {
        raise RuntimeError("e2e: neojac not on PATH (set JAC)");
    }
    return got;
}

impl native_bin(entry_mod: str) -> str {
    env_key: str = "JACKAL_TUI_BIN" if entry_mod.startswith("tui") else "JACKAL_BIN";
    pre: str = os.environ.get(env_key, "");
    if pre {
        return pre;
    }
    out_dir: str = os.path.join(app_dir(), ".jac", "e2e");
    os.makedirs(out_dir, exist_ok=True);
    out: str = os.path.join(out_dir, os.path.basename(entry_mod).replace(".jac", ""));
    if out in _built_bins {
        return out;
    }
    r = subprocess.run(
        [jac_bin(), "build", entry_mod, "-o", out],
        cwd=app_dir(),
        capture_output=True,
        text=True,
        timeout=1800,
    );
    if r.returncode != 0 {
        raise RuntimeError("e2e: neojac build " + entry_mod + " failed:\n" + r.stdout + r.stderr);
    }
    _built_bins.append(out);
    os.environ[env_key] = out;
    return out;
}

impl Sandbox.write(rel: str, text: str) {
    path: str = os.path.join(self.project, rel);
    os.makedirs(os.path.dirname(path) or self.project, exist_ok=True);
    fh: any = open(path, "w", encoding="utf-8");
    fh.write(text);
    fh.close();
}

impl Sandbox.read(rel: str) -> str {
    fh: any = open(os.path.join(self.project, rel), "r", encoding="utf-8");
    txt: str = fh.read();
    fh.close();
    return txt;
}

impl Sandbox.exists(rel: str) -> bool {
    return os.path.exists(os.path.join(self.project, rel));
}

impl Sandbox.script(steps: list[dict[str, any]]) {
    fh: any = open(self.script_path, "w", encoding="utf-8");
    fh.write(json.dumps(steps));
    fh.close();
}

impl Sandbox.calls -> list[dict[str, any]] {
    if not os.path.exists(self.log_path) {
        return [];
    }
    out: list[dict[str, any]] = [];
    fh: any = open(self.log_path, "r", encoding="utf-8");
    for line in fh.read().splitlines() {
        if line.strip() {
            out.append(json.loads(line));
        }
    }
    fh.close();
    return out;
}

impl Sandbox.cleanup {
    shutil.rmtree(self.base_dir, ignore_errors=True);
}

impl Sandbox.explain(r: any) -> str {
    return r.describe() + "\n--- model calls ---\n" + json.dumps(self.calls(), indent=1)[:6000];
}

impl make_sandbox(files: dict[str, str] | None = None) -> Sandbox {
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
    cfg_fh: any = open(os.path.join(sb.agent_dir, "config.json"), "w");
    cfg_fh.write("{}");
    cfg_fh.close();
    if files is not None {
        for (rel, text) in files.items() {
            sb.write(rel, text);
        }
    }
    return sb;
}

impl RunResult.events -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for line in self.stdout.splitlines() {
        line = line.strip();
        if not line.startswith("{") {
            continue;
        }
        try {
            ev: any = json.loads(line);
            if isinstance(ev, dict) {
                out.append(ev);
            }
        } except ValueError {}
    }
    return out;
}

impl RunResult.event_types -> list[str] {
    return [str(e.get("type", "")) for e in self.events()];
}

impl RunResult.describe -> str {
    return "exit="
        + str(self.code)
        + "\n--- stdout ---\n"
        + self.stdout[-4000:]
        + "\n--- stderr ---\n"
        + self.stderr[-4000:];
}

impl run_jackal(
    sb: Sandbox,
    args: list[str],
    stdin_text: str = "",
    env_extra: dict[str, str] | None = None,
    timeout_s: int = E2E_TIMEOUT_S,
) -> RunResult {
    env: dict[str, str] = dict(os.environ);
    for k in [
        "OPENROUTER_API_KEY",
        "OPENAI_API_KEY",
        "DEEPSEEK_API_KEY",
        "ZAI_API_KEY",
        "JACKAL_MODE",
        "JAC_HANDOFF",
    ] {
        env.pop(k, None);
    }
    env["JACKAL_MODEL"] = "mock";
    env["JACKAL_MOCK_SCRIPT"] = sb.script_path;
    env["JACKAL_MOCK_LOG"] = sb.log_path;
    env["JACKAL_AGENT_DIR"] = sb.agent_dir;
    env["NO_COLOR"] = "1";
    env["JACKAL_MCP_NO_IMPORT"] = "1";
    if env_extra is not None {
        for (k, v) in env_extra.items() {
            env[k] = v;
        }
    }
    cmd: list[str] = [native_bin("main.jac")] + args;
    try {
        proc: any = subprocess.run(
            cmd,
            input=stdin_text,
            capture_output=True,
            text=True,
            cwd=sb.project,
            env=env,
            timeout=timeout_s,
        );
    } except subprocess.TimeoutExpired as e {
        return RunResult(
            code=-9,
            stdout=str(e.stdout or ""),
            stderr="TIMEOUT after " + str(timeout_s) + "s\n" + str(e.stderr or ""),
        );
    }
    return RunResult(code=int(proc.returncode), stdout=str(proc.stdout), stderr=str(proc.stderr));
}

impl jsonl(kind: str, text: str = "", extra: dict[str, any] | None = None) -> str {
    req: dict[str, any] = {"type": kind, "text": text};
    if extra is not None {
        for (k, v) in extra.items() {
            req[k] = v;
        }
    }
    return json.dumps(req) + "\n";
}

impl TuiSession._read_loop {
    dec: any = codecs.getincrementaldecoder("utf-8")("replace");
    while self.alive {
        try {
            chunk: bytes = os.read(self.master_fd, 65536);
        } except OSError {
            break;
        }
        if not chunk {
            break;
        }
        text: str = dec.decode(chunk);
        self.lock.acquire();
        try {
            self.raw.append(text);
            if self.screen is not None {
                self.screen.write(text);
            }
        } finally {
            self.lock.release();
        }
    }
    self.alive = False;
}

impl TuiSession.send(data: str) {
    os.write(self.master_fd, data.encode("utf-8"));
}

impl TuiSession.type_text(text: str, delay_s: float = 0.005) {
    for ch in text {
        self.send(ch);
        time.sleep(delay_s);
    }
}

impl TuiSession.press(key: str) {
    self.send(KEYS.get(key, key));
}

impl TuiSession.screen_text -> str {
    self.lock.acquire();
    try {
        return self.screen.viewport_text() if self.screen is not None else "";
    } finally {
        self.lock.release();
    }
}

impl TuiSession.raw_output -> str {
    self.lock.acquire();
    try {
        return "".join(self.raw);
    } finally {
        self.lock.release();
    }
}

impl TuiSession.wait_for(needle: str, timeout_s: float = 60.0) -> str {
    deadline: float = time.time() + timeout_s;
    while time.time() < deadline {
        txt: str = self.screen_text();
        if needle in txt {
            return txt;
        }
        if not self.alive and self.proc.poll() is not None {
            break;
        }
        time.sleep(0.05);
    }
    raise AssertionError(
        "timed out waiting for "
            + repr(needle)
            + "\n--- screen ---\n"
            + self.screen_text()
            + "\n--- exit: "
            + str(self.proc.poll()),
    );
}

impl TuiSession.wait_gone(needle: str, timeout_s: float = 30.0) -> str {
    deadline: float = time.time() + timeout_s;
    while time.time() < deadline {
        txt: str = self.screen_text();
        if needle not in txt {
            return txt;
        }
        if not self.alive and self.proc.poll() is not None {
            break;
        }
        time.sleep(0.05);
    }
    raise AssertionError(
        "timed out waiting for "
            + repr(needle)
            + " to disappear\n--- screen ---\n"
            + self.screen_text()
            + "\n--- exit: "
            + str(self.proc.poll()),
    );
}

impl TuiSession.wait_exit(timeout_s: float = 30.0) -> int | None {
    try {
        return int(self.proc.wait(timeout=timeout_s));
    } except subprocess.TimeoutExpired {
        return None;
    }
}

impl TuiSession.close {
    if self.proc is not None and self.proc.poll() is None {
        try {
            os.killpg(int(self.proc.pid), 15);
        } except Exception {}
        try {
            self.proc.wait(timeout=10);
        } except Exception {
            try {
                os.killpg(int(self.proc.pid), 9);
            } except Exception {}
        }
    }
    self.alive = False;
    try {
        os.close(self.master_fd);
    } except OSError {}
}

impl spawn_tui(
    sb: Sandbox,
    cols: int = 100,
    rows: int = 30,
    env_extra: dict[str, str] | None = None,
    boot_timeout_s: float = 240.0,
) -> TuiSession {
    (master_fd, slave_fd) = pty.openpty();
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0));
    env: dict[str, str] = dict(os.environ);
    for k in [
        "OPENROUTER_API_KEY",
        "OPENAI_API_KEY",
        "DEEPSEEK_API_KEY",
        "ZAI_API_KEY",
        "JACKAL_MODE",
        "JAC_HANDOFF",
    ] {
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
        for (k, v) in env_extra.items() {
            env[k] = v;
        }
    }
    cmd: list[str] = [native_bin("tui/shell.jac")];
    proc: any = subprocess.Popen(
        cmd,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        cwd=sb.project,
        env=env,
        start_new_session=True,
        close_fds=True,
    );
    os.close(slave_fd);
    sess = TuiSession(
        proc=proc,
        master_fd=master_fd,
        screen=EmulatedTerminal(cols, rows),
        raw=[],
        lock=threading.Lock(),
        alive=True,
    );
    sess.reader = threading.Thread(target=sess._read_loop, daemon=True);
    sess.reader.start();
    sess.wait_for("\u276f", boot_timeout_s);
    return sess;
}

impl fixture_path(name: str) -> str {
    return os.path.join(app_dir(), "e2e", "fixtures", name);
}

impl write_project_config(sb: Sandbox, cfg: dict[str, any]) {
    sb.write(".jackal/config.json", json.dumps(cfg));
}
