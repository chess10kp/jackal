impl _key_env(provider_id: str) -> str {
    route: any = PROVIDER_ROUTES.get(provider_id, {});
    return str(route.get("key_env", "") or "") if isinstance(route, dict) else "";
}

impl _stored_key_for_route(stored: dict[str, any], route_id: str) -> str {
    direct = stored_api_key(stored, route_id);
    if direct {
        return direct;
    }
    aliases: any = _ROUTE_STORED_ALIASES.get(route_id, []);
    if isinstance(aliases, list) {
        for alias in aliases {
            got = stored_api_key(stored, str(alias));
            if got {
                return got;
            }
        }
    }
    return "";
}

impl _models_json_openai_base(path: str) -> str {
    if not os.path.isfile(path) {
        return "";
    }
    fh: any = None;
    try {
        fh = open(path, "r");
        raw: any = json.load(fh);
    } except (OSError, ValueError) {
        return "";
    } finally {
        if fh is not None {
            fh.close();
        }
    }
    if not isinstance(raw, dict) {
        return "";
    }
    providers: any = raw.get("providers", {});
    if not isinstance(providers, dict) {
        return "";
    }
    openai: any = providers.get("openai", {});
    if not isinstance(openai, dict) {
        return "";
    }
    base: any = openai.get("baseUrl", openai.get("base_url", ""));
    if isinstance(base, str) and base.strip() {
        return base.strip().rstrip("/");
    }
    return "";
}

impl apply_pi_models_environment {
    if os.environ.get("OPENAI_COMPAT_BASE", "") {
        return;
    }
    paths: list[str] = [];
    agent_dir = os.environ.get("JACKAL_AGENT_DIR", "");
    if agent_dir {
        paths.append(os.path.join(agent_dir, "models.json"));
    }
    paths.append(os.path.join(pi_agent_dir(), "models.json"));
    for p in paths {
        base = _models_json_openai_base(p);
        if base {
            os.environ["OPENAI_COMPAT_BASE"] = base;
            _hydrated_envs.add("OPENAI_COMPAT_BASE");
            return;
        }
    }
}

impl hydrate_auth_environment -> list[str] {
    stored = load_auth_merged(resolve_auth_path());
    apply_pi_models_environment();
    done: list[str] = [];
    for prov in PROVIDER_ROUTES {
        provider_id = str(prov);
        key_env = _key_env(provider_id);
        if not key_env or os.environ.get(key_env, "") {
            continue;
        }
        key = _stored_key_for_route(stored, provider_id);
        if key {
            os.environ[key_env] = key;
            _hydrated_envs.add(key_env);
            done.append(provider_id);
        }
    }
    for auth_id in _PI_EXTRA_KEY_ENVS {
        env_name = _PI_EXTRA_KEY_ENVS[auth_id];
        if os.environ.get(env_name, "") {
            continue;
        }
        extra = stored_api_key(stored, auth_id);
        if extra {
            os.environ[env_name] = extra;
            _hydrated_envs.add(env_name);
        }
    }
    return done;
}

impl note_hydrated(key_env: str) {
    if key_env {
        _hydrated_envs.add(key_env);
    }
}

impl logout_provider(provider_id: str) -> str {
    if provider_id == "openai" {
        return logout_account();
    }
    if provider_id not in PROVIDER_ROUTES {
        return "unknown provider: " + provider_id;
    }
    path = resolve_auth_path();
    data = load_auth_file(path);
    key_env = _key_env(provider_id);
    had: bool = has_credential(data, provider_id);
    if had and not save_auth_file(path, credential_remove(data, provider_id)) {
        return "ERROR: could not update " + path;
    }
    if key_env and key_env in _hydrated_envs {
        os.environ.pop(key_env, None);
        _hydrated_envs.discard(key_env);
        return "logged out of " + provider_id;
    }
    if key_env and os.environ.get(key_env, "") {
        prefix: str = "removed stored credential; " if had else "";
        return prefix + key_env + " is still set in the environment";
    }
    return ("logged out of " + provider_id) if had else ("no stored credential for " + provider_id);
}

impl stored_providers -> list[str] {
    data = load_auth_file(resolve_auth_path());
    out: list[str] = [];
    for prov in PROVIDER_ROUTES {
        if configured_account() if str(prov) == "openai" else has_credential(data, str(prov)) {
            out.append(str(prov));
        }
    }
    return out;
}
