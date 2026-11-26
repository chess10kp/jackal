import sys;
import json;

def get_history -> list[dict[str, any]];
def restore_history(msgs: list[dict[str, any]]);

def set_current_session_id(sid: str);
def cancel_active_turn -> bool;
def list_commands -> dict[str, any];
def run_command(name: str, args: str = "") -> str;
def run_extension_shortcut(key: str) -> str;
def list_extension_shortcuts -> dict[str, any];
def list_extension_labels -> dict[str, any];
def json_event(kind: str, data: dict[str, any]);
