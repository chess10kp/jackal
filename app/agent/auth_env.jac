import os;

glob _hydrated_envs: set[str] = set();

def _key_env(provider_id: str) -> str;
def hydrate_auth_environment -> list[str];
def note_hydrated(key_env: str);
def logout_provider(provider_id: str) -> str;
def stored_providers -> list[str];
