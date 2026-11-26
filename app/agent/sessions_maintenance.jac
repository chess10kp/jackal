import os;
import time;
import datetime;
def _iso_to_epoch(stamp: str) -> float | None;
def prune_sessions(cwd: str, max_count: int = 0, retention_days: int = 0) -> int;
def latest_session_id(cwd: str) -> str | None;
def export_session(cwd: str, session_id: str, path: str) -> bool;
