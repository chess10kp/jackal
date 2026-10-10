"""Bridge stored credentials (auth.json) into provider env vars.

Transports read API keys from the environment only; every frontend calls
hydrate_auth_environment once at startup so keys saved by /login work in the
TUI, the line REPL, JSONL, and print mode alike.
"""

import os;
import from .llm { PROVIDER_ROUTES }
import from .auth {
    load_auth_file, save_auth_file, resolve_auth_path, stored_api_key,
    credential_remove, has_credential,
}

"""Env vars this process set from auth.json (so logout may unset them)."""
glob _hydrated_envs: set[str] = set();


def _key_env(provider_id: str) -> str {
    route: any = PROVIDER_ROUTES.get(provider_id, {});
    return str(route.get("key_env", "") or "") if isinstance(route, dict) else "";
}


"""Export stored API keys for providers whose env var is unset. Explicit
environment values always win. Returns the providers hydrated."""
def hydrate_auth_environment() -> list[str] {
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


"""Remember that `key_env` now carries a stored credential (set by /login)."""
def note_hydrated(key_env: str) {
    if key_env { _hydrated_envs.add(key_env); }
}


"""Remove a provider's stored credential. The env var is cleared only when it
came from auth.json; a key exported by the user's shell is left alone and
reported. Returns a status line."""
def logout_provider(provider_id: str) -> str {
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


"""Providers with a stored credential (for /logout completion and listing)."""
def stored_providers() -> list[str] {
    data = load_auth_file(resolve_auth_path());
    out: list[str] = [];
    for prov in PROVIDER_ROUTES {
        if has_credential(data, str(prov)) { out.append(str(prov)); }
    }
    return out;
}
