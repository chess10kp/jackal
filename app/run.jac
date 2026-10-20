"""Launch Jackal's native TUI from this app directory."""

import os;
import subprocess;
import sys;


with entry:__main__ {
    app_dir: str = os.path.dirname(os.path.abspath(__file__));
    repo_root: str = os.path.dirname(app_dir);
    env: dict[str, str] = dict(os.environ);
    env["JACKAL_ROOT"] = repo_root;
    env["JACKAL_AGENT_DIR"] = os.path.join(repo_root, "pi");

    proc: any = subprocess.run(
        ["jac", "run", "tui/shell.jac"],
        cwd=app_dir,
        env=env,
    );
    sys.exit(int(proc.returncode));
}
