import os;
import json;
import stat;
import time;
import copy;

glob AUTH_FILE_NAME: str = "auth.json";

glob DEFAULT_AGENT_DIR_NAME: str = ".jackal";

glob KNOWN_AUTH_TYPES: list[str] = ["oauth", "api_key", "env"];

glob OAUTH_REQUIRED_KEYS: list[str] = ["refresh", "access"];

import from c {
    def chmod(path: str, mode: i32) -> i32;
}

def _path_abspath(p: str) -> str;

def _path_expanduser(p: str) -> str;

def _path_dirname(p: str) -> str;

def _file_chmod(p: str, mode: int);
def resolve_auth_path(agent_dir: str = "") -> str;
def load_auth_file(path: str) -> dict[str, any];

def save_auth_file(path: str, data: dict[str, any]) -> bool;
def validate_credential(cred: any) -> dict[str, any] | None;
def credential_get(data: dict[str, any], provider: str) -> dict[str, any] | None;
def credential_set(data: dict[str, any], provider: str, cred: dict[str, any]) -> dict[str, any];
def credential_remove(data: dict[str, any], provider: str) -> dict[str, any];
def has_credential(data: dict[str, any], provider: str) -> bool;
def now_ms -> int;
def is_expired(cred: any, at_ms: int = -1) -> bool;
def stored_api_key(data: dict[str, any], provider: str, at_ms: int = -1) -> str | None;
def get_auth_status(
    provider: str,
    stored_providers: dict[str, any],
    runtime_keys: list[str] | None = None,
    env_api_key: str = "",
) -> dict[str, any];
