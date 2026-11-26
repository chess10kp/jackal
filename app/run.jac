import os;
import shutil;
import subprocess;
import sys;

def _jac_launcher(repo_root: str) -> str;

with entry:__main__ {
    app_dir: str = os.path.dirname(os.path.abspath(__file__));
    repo_root: str = os.path.dirname(app_dir);
    env: dict[str, str] = dict(os.environ);
    env["JACKAL_ROOT"] = repo_root;
    env["JACKAL_AGENT_DIR"] = os.path.join(repo_root, "pi");
    env.pop("JAC_HANDOFF", None);
    argv: list[str] = [_jac_launcher(repo_root), "run", "tui/shell.jac"];
    for extra in sys.argv[1:] {
        argv.append(extra);
    }
    proc: any = subprocess.run(argv, cwd=app_dir, env=env);
    sys.exit(int(proc.returncode));
}
