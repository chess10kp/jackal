impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_expanduser(p: str) -> str {
    return str(os.path.expanduser(p));
}

impl _path_dirname(p: str) -> str {
    return str(os.path.dirname(p));
}

impl _file_chmod(p: str, mode: int) {
    chmod(p, i32(mode));
}

impl resolve_auth_path(agent_dir: str = "") -> str {
    base = agent_dir;
    if not base {
        base = os.environ.get("JACKAL_AGENT_DIR") or "";
    }
    if not base {
        base = os.path.join(_path_expanduser("~"), DEFAULT_AGENT_DIR_NAME);
    }
    return os.path.join(base, AUTH_FILE_NAME);
}

impl load_auth_file(path: str) -> dict[str, any] {
    if not os.path.isfile(path) {
        return {};
    }
    fh: any = None;
    try {
        fh = open(path, "r");
        raw = json.load(fh);
    } except (OSError, ValueError) {
        return {};
    } finally {
        if fh is not None {
            fh.close();
        }
    }
    if isinstance(raw, dict) {
        return raw;
    }
    return {};
}

impl save_auth_file(path: str, data: dict[str, any]) -> bool {
    parent = _path_dirname(_path_abspath(path));
    try {
        if not os.path.isdir(parent) {
            os.makedirs(parent, mode=0o700, exist_ok=True);
        }
        fh = open(path, "w");
        fh.write(json_pretty(json.dumps(data)));
        fh.write("\n");
        fh.close();
        _file_chmod(path, stat.S_IRUSR | stat.S_IWUSR);
        return True;
    } except OSError {
        return False;
    }
}

impl validate_credential(cred: any) -> dict[str, any] | None {
    if not isinstance(cred, dict) {
        return None;
    }
    ctype = cred.get("type");
    if ctype == "api_key" {
        key = cred.get("key");
        if not isinstance(key, str) or not key {
            return None;
        }
        out: dict[str, any] = {"type": "api_key", "key": key};
    } elif ctype == "oauth" {
        for field in OAUTH_REQUIRED_KEYS {
            if not isinstance(cred.get(field), str) or not cred[field] {
                return None;
            }
        }
        expires = cred.get("expires");
        if not isinstance(expires, (int, float)) or isinstance(expires, bool) {
            return None;
        }
        out = {
            "type": "oauth",
            "access": cred["access"],
            "refresh": cred["refresh"],
            "expires": expires,
        };
    } else {
        return None;
    }
    for (k, v) in cred.items() {
        if k not in out {
            out[k] = v;
        }
    }
    return out;
}

impl credential_get(data: dict[str, any], provider: str) -> dict[str, any] | None {
    if provider not in data {
        return None;
    }
    return validate_credential(data[provider]);
}

impl credential_set(data: dict[str, any], provider: str, cred: dict[str, any]) -> dict[str, any] {
    nxt = dict(data);
    nxt[provider] = cred;
    return nxt;
}

impl credential_remove(data: dict[str, any], provider: str) -> dict[str, any] {
    nxt: dict[str, any] = {};
    for (k, v) in data.items() {
        if k != provider {
            nxt[k] = v;
        }
    }
    return nxt;
}

impl has_credential(data: dict[str, any], provider: str) -> bool {
    return credential_get(data, provider) is not None;
}

impl now_ms -> int {
    return int(time.time() * 1000);
}

impl is_expired(cred: any, at_ms: int = -1) -> bool {
    if not isinstance(cred, dict) {
        return True;
    }
    if cred.get("type") == "api_key" and isinstance(cred.get("key"), str) and cred["key"] {
        return False;
    }
    if cred.get("type") != "oauth" {
        return True;
    }
    expires = cred.get("expires");
    if not isinstance(expires, (int, float)) or isinstance(expires, bool) {
        return True;
    }
    now = at_ms if at_ms >= 0 else now_ms();
    return now >= expires;
}

impl stored_api_key(data: dict[str, any], provider: str, at_ms: int = -1) -> str | None {
    cred = credential_get(data, provider);
    if cred is None or is_expired(cred, at_ms) {
        return None;
    }
    if cred["type"] == "api_key" {
        return str(cred["key"]);
    }
    return str(cred.get("access", ""));
}

impl get_auth_status(
    provider: str,
    stored_providers: dict[str, any],
    runtime_keys: list[str] | None = None,
    env_api_key: str = "",
) -> dict[str, any] {
    runtimes = runtime_keys if runtime_keys is not None else [];
    if provider in runtimes {
        return {"configured": True, "source": "stored", "label": "runtime override"};
    }
    if provider in stored_providers {
        return {"configured": True, "source": "stored"};
    }
    if env_api_key {
        return {"configured": True, "source": "environment", "label": "env"};
    }
    return {"configured": False};
}
