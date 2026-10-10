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
    has root: str = "",
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
        shutil.rmtree(self.root, ignore_errors=True);
    }
}


def make_sandbox(files: dict[str, str] | None = None) -> Sandbox {
    root: str = tempfile.mkdtemp(prefix="jackal-e2e-");
    sb = Sandbox(
        root=root,
        project=os.path.join(root, "project"),
        agent_dir=os.path.join(root, "agent"),
        script_path=os.path.join(root, "script.json"),
        log_path=os.path.join(root, "calls.jsonl"),
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
    env["HOME"] = sb.root;
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
