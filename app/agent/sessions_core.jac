import os;
import json;
import time;
import re;
import datetime;

glob _last_id_ms: int = 0,
     _SESSION_ID_PATTERN: str = r"^sess_[0-9]+$",
     _DEFAULT_NAME: str = "new session",
     _INDEX_NAME: str = "index.json",
     _LEGACY_INDEX_NAME: str = "latest.json",
     _TRANSCRIPT_SUFFIX: str = ".json";
def _path_abspath(p: str) -> str;

def _path_dirname(p: str) -> str;

def _sessions_dir(cwd: str) -> str;

def _session_path(cwd: str, session_id: str) -> str;

def _index_path(cwd: str) -> str;

def is_valid_session_id(session_id: str) -> bool;
def _next_epoch_ms -> int;
def new_session_id -> str;
def _iso_from_ms(ms: int) -> str;

def _now_iso -> str;
def _read_json(path: str) -> any;
def _write_json(path: str, data: any) -> bool;
def _is_record(rec: any) -> bool;
def _is_index_entry(item: any) -> bool;

def _entry_sort_key(rec: dict[str, any]) -> str;
def _newest_first(entries: list[dict[str, any]]) -> list[dict[str, any]];
def _read_index(cwd: str) -> tuple[list[dict[str, any]], bool];

def _write_index(cwd: str, entries: list[dict[str, any]]) -> bool;
def _upsert_index_entry(cwd: str, rec: dict[str, any]) -> bool;
def _scan_directory(cwd: str) -> list[dict[str, any]];
def save_session(
    cwd: str, history: list[dict[str, any]], name: str = "", session_id: str = "", model: str = ""
) -> dict[str, any];
def get_session_record(cwd: str, session_id: str) -> dict[str, any] | None;
def load_session(cwd: str, session_id: str) -> list[dict[str, any]];
def list_sessions(cwd: str) -> list[dict[str, any]];
def rename_session(cwd: str, session_id: str, name: str) -> bool;
def delete_session(cwd: str, session_id: str) -> bool;
