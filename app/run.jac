"""Launch Jackal's native TUI from this app directory.

`run.sh` is the supported entry (it avoids this second process entirely).
This exists for `jac run run.jac` by hand, so it must still pick the
workspace compiler: a bare "jac" here resolves to whatever is on PATH,
which is frequently a different build than ./jac.
"""

import os;
import shutil;
import subprocess;
import sys;


def _jac_launcher(repo_root: str) -> str {
    workspace = os.path.join(repo_root, "jac");
    if os.path.isfile(workspace) and os.access(workspace, os.X_OK) {
        return workspace;
    }
    found = shutil.which("jac");
    return found if found else "jac";
}

with entry:__main__ {
    app_dir: str = os.path.dirname(os.path.abspath(__file__));
    repo_root: str = os.path.dirname(app_dir);
    env: dict[str, str] = dict(os.environ);
    env["JACKAL_ROOT"] = repo_root;
    env["JACKAL_AGENT_DIR"] = os.path.join(repo_root, "pi");
    # An inherited handoff endpoint makes the child `jac` wait on a parent
    # that is itself waiting on us.
    env.pop("JAC_HANDOFF", None);
    argv: list[str] = [_jac_launcher(repo_root), "run", "tui/shell.jac"];
    for extra in sys.argv[1:] {
        argv.append(extra);
    }
    proc: any = subprocess.run(argv, cwd=app_dir, env=env);
    sys.exit(int(proc.returncode));
}
