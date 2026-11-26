import os;
import json;
import shutil;
import subprocess;
import datetime;

glob _MAX_CHECKPOINT_FILES: int = 500,
     _DESCRIPTION_LENGTH: int = 80,
     _INVALID_NAME_CHARS: str = '<>:"/\\|?*',
     _METADATA_NAME: str = "metadata.json",
     _CONVERSATION_NAME: str = "conversation.json";
def _path_dirname(p: str) -> str;

def _path_abspath(p: str) -> str;

def _path_relpath(p: str, start: str) -> str;

def checkpoints_dir(cwd: str) -> str;

def _checkpoint_path(cwd: str, name: str) -> str;

def validate_checkpoint_name(name: str) -> dict[str, any];
def _generate_checkpoint_name -> str;

def _generate_description(messages: list[dict[str, any]]) -> str;
def _git_commit_hash(cwd: str) -> str | None;
def get_modified_files(cwd: str) -> list[str];
def _resolve_rel(cwd: str, rel: str) -> str;
def _capture_files(cwd: str, file_paths: list[str]) -> dict[str, str];

def _dir_size(dir_path: str) -> int;

def _write_json(path: str, data: any) -> bool;
def _load_json_file(path: str) -> any;
def create_checkpoint(
    cwd: str,
    messages: list[dict[str, any]],
    provider: str,
    model: str,
    name: str = "",
    modified_files: list[str] | None = None,
) -> dict[str, any];
def load_checkpoint(cwd: str, name: str) -> dict[str, any];

def _timestamp_key(item: dict[str, any]) -> str;
def list_checkpoints(cwd: str) -> list[dict[str, any]];
def delete_checkpoint(cwd: str, name: str);
def restore_checkpoint_files(cwd: str, snapshots: dict[str, str]);

def _plural(n: int, unit: str) -> str;

def _changed_count(m: dict[str, any]) -> int;
def format_relative_time(timestamp: str) -> str;

def _size_label(size_bytes: any) -> str;
def format_checkpoint_overlay_row(item: dict[str, any]) -> str;

def format_checkpoint_list(items: list[dict[str, any]]) -> str;
