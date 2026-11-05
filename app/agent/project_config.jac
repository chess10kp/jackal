"""Native leaf for discovering and reading project-level `.jackal` config."""

import json;
import os;


def _path_abspath(path: str) -> str {
    return str(os.path.abspath(path));
}


def _path_dirname(path: str) -> str {
    return str(os.path.dirname(path));
}


def:pub load_project_config(cwd: str) -> dict[str, any] {
    cur: str = _path_abspath(cwd);
    while True {
        candidate: str = os.path.join(cur, ".jackal");
        if os.path.isdir(candidate) {
            candidate = os.path.join(candidate, "config.json");
        }
        if os.path.isfile(candidate) {
            try {
                with open(candidate, "r", encoding="utf-8") as fh {
                    parsed: any = json.load(fh);
                }
                if isinstance(parsed, dict) {
                    return parsed as dict[str, any];
                }
            } except Exception {
                return {};
            }
        }
        parent: str = _path_dirname(cur);
        if parent == cur {
            return {};
        }
        cur = parent;
    }
}
