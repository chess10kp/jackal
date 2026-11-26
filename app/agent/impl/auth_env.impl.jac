impl _key_env(provider_id: str) -> str {
    route: any = PROVIDER_ROUTES.get(provider_id, {});
    return str(route.get("key_env", "") or "") if isinstance(route, dict) else "";
}

impl hydrate_auth_environment -> list[str] {
    stored = load_auth_file(resolve_auth_path());
    done: list[str] = [];
    for prov in PROVIDER_ROUTES {
        provider_id = str(prov);
        key_env = _key_env(provider_id);
        if not key_env or os.environ.get(key_env, "") {
            continue;
        }
        key = stored_api_key(stored, provider_id);
        if key {
            os.environ[key_env] = key;
            _hydrated_envs.add(key_env);
            done.append(provider_id);
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
        if has_credential(data, str(prov)) {
            out.append(str(prov));
        }
    }
    return out;
}
