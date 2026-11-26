import os;
import json;
import datetime;

glob LOG_LEVELS: dict[str, int] = {
         "debug": 10,
         "info": 20,
         "warn": 30,
         "warning": 30,
         "error": 40,
         "off": 100,
     },
     LOG_ENV: str = "JACKAL_LOG",
     LEVEL_ENV: str = "JACKAL_LOG_LEVEL",
     DEFAULT_LOG_DIR: str = ".jackal/logs",
     DEFAULT_LEVEL: str = "info",
     MAX_FIELD_DEPTH: int = 3,
     MAX_FIELD_ITEMS: int = 20,
     MAX_STRING_LEN: int = 400,
     MAX_TRACEBACK_LEN: int = 4000;

glob _FALSEY: list[str] = ["0", "off", "false", "no", "none", ""],
     _TRUTHY: list[str] = ["1", "on", "true", "yes"];
def log_sink -> str;

sem log_sink = "Resolve the JSONL sink path from JACKAL_LOG; empty means disabled.";
def log_threshold -> int;

sem log_threshold = "Numeric severity threshold for the env-configured log level.";
def log_enabled(level: str = "info") -> bool;

sem log_enabled = "Cheap pre-check for callers that would build an expensive payload.";
def safe_fields(value: any, depth: int = 0) -> any;

sem safe_fields = "Best-effort JSON-safe projection of arbitrary logging payloads.";
def _short_repr(value: any) -> str;
def log_event(level: str, source: str, message: str, fields: dict[str, any] | None = None) -> bool;

sem log_event = "Write one structured JSONL log record; never raises into the caller.";
def _format_tb(exc: any) -> str;
def log_exception(source: str, exc: any, fields: dict[str, any] | None = None) -> bool;

sem log_exception = "Log a swallowed exception (type, message, traceback) at error level.";

def log_debug(source: str, message: str, fields: dict[str, any] | None = None) -> bool;

def log_info(source: str, message: str, fields: dict[str, any] | None = None) -> bool;

def log_warn(source: str, message: str, fields: dict[str, any] | None = None) -> bool;
def read_log(path: str) -> list[dict[str, any]];

sem read_log = "Parse a JSONL log file into records, skipping malformed lines.";
