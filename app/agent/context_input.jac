import os;
import re;
import subprocess;

glob _FILE_MENTION_PATTERN: str = r"@([^\s:]+)(?::(\d+)(?:-(\d+))?)?",
     _MENTION_RANGE_PATTERN: str = r"^\d+(-\d+)?$",
     _CURSOR_RANGE_FULL: str = r"^(.+?)(:\d+(?:-\d*)?)$",
     _WINDOWS_DRIVE_PATTERN: str = r"^[a-zA-Z]:[/\\]",
     _MAX_FILE_CHARS: int = 80000,
     _TOKEN_WARN_CHARS: int = 40000,
     _COMMAND_TIMEOUT_SECS: float = 60.0;
def _path_abspath(p: str) -> str;

def _path_normpath(p: str) -> str;
def is_valid_file_path(file_path: str) -> bool;
def parse_line_range(range_str: str) -> dict[str, any] | None;
def parse_file_mentions(input_text: str) -> list[dict[str, any]];
def parse_mention_token(raw: str) -> dict[str, any];
def get_current_file_mention(input_text: str, cursor_position: int = -1) -> dict[str, any] | None;
def _safe_resolve(cwd: str, input_path: str) -> str;
def _load_file_slice(cwd: str, mention: str, line_range: any = None) -> tuple[str, int];
def _run_inline_command(cwd: str, command: str) -> str;
def expand_context_input(cwd: str, text: str) -> str;
