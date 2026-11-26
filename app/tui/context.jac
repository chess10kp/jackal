import os;
import re;
def _explorer_walk(dir_path: str, base_root: str, depth: int, out: list[str]);

def _explorer_file_entries(cwd: str) -> dict[str, list[str]];
def _skills_picker_entries(skills: list[dict[str, any]]) -> dict[str, list[str]];
def _format_mentions(paths: list[str]) -> str;
def _take_quoted_mentions(text: str) -> tuple[str, list[dict[str, any]]];
def _expand_quoted_context(cwd: str, text: str) -> str;
def _insert_into_draft(app: LiveShell, addition: str);
def _open_explorer_picker(app: LiveShell) -> str;
