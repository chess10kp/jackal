"""Bridge stored credentials (auth.json) into provider env vars.

Transports read API keys from the environment only; every frontend calls
hydrate_auth_environment once at startup so keys saved by /login work in the
TUI, the line REPL, JSONL, and print mode alike.
"""

import os;
import from .provider_routes { PROVIDER_ROUTES, PROVIDER_IDS }
import from .auth_credentials {
    load_auth_file, save_auth_file, resolve_auth_path, stored_api_key,
    credential_remove, has_credential,
}

"""Env vars this process set from auth.json (so logout may unset them)."""
glob _hydrated_envs: set[str] = set();


def _key_env(provider_id: str) -> str {
    if provider_id not in PROVIDER_IDS { return ""; }
    route: dict[str, any] = PROVIDER_ROUTES[provider_id];
    return str(route["key_env"] or "");
}


"""Export stored API keys for providers whose env var is unset. Explicit
environment values always win. Returns the providers hydrated."""
def:pub hydrate_auth_environment() -> list[str] {
    stored: dict[str, any] = load_auth_file(resolve_auth_path());
    done: list[str] = [];
    for provider_id in PROVIDER_IDS {
        key_env: str = _key_env(provider_id);
        if not key_env or os.environ.get(key_env, "") {
            continue;
        }
        key: str = stored_api_key(stored, provider_id) or "";
        if key {
            os.environ[key_env] = key;
            _hydrated_envs.add(key_env);
            done.append(provider_id);
        }
    }
    return done;
}


"""Remember that `key_env` now carries a stored credential (set by /login)."""
def:pub note_hydrated(key_env: str) {
    if key_env { _hydrated_envs.add(key_env); }
}


"""Remove a provider's stored credential. The env var is cleared only when it
came from auth.json; a key exported by the user's shell is left alone and
reported. Returns a status line."""
def:pub logout_provider(provider_id: str) -> str {
    if provider_id not in PROVIDER_IDS {
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
def:pub stored_providers() -> list[str] {
    data: dict[str, any] = load_auth_file(resolve_auth_path());
    out: list[str] = [];
    for provider_id in PROVIDER_IDS {
        if has_credential(data, provider_id) { out.append(provider_id); }
    }
    return out;
}
