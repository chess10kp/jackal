import os;
import re;
import fnmatch;

glob MAX_NAME_LENGTH: int = 64,
     MAX_DESCRIPTION_LENGTH: int = 1024,
     IGNORE_FILE_NAMES: list[str] = [".gitignore", ".ignore", ".fdignore"];
def _base_name(p: str) -> str;

def _dir_name(p: str) -> str;

def _rel_path(target: str, start: str) -> str;

def _abs_path(p: str) -> str;
def _canonical(p: str) -> str;

def _is_abs(p: str) -> bool;

def _user_home -> str;

def _parse_scalar(value: str) -> any;
def parse_frontmatter(content: str) -> tuple[dict[str, any], str];
def frontmatter_string(value: any) -> str | None;
def _gitignore_parse_rules(content: str, prefix: str) -> list[str];
def _load_ignore_rules(root_dir: str, subdir: str) -> list[str];
def _match_ignore_pattern(path: str, rules: list[str]) -> bool;

def _validate_name(name: str) -> list[str];

def _validate_description(description: str | None) -> list[str];

def _warning(message: str, path: str) -> dict[str, any];
def _load_skill_from_file(file_path: str, source: str) -> tuple[dict[str, any]
    | None, list[dict[str, any]]];
