import os;
import json;
import re;

glob SUBAGENT_TOOL_ALIASES: dict[str, str] = {
         "read_file": "read",
         "write_file": "write",
         "edit_file": "edit",
         "grep": "bash",
         "find": "bash",
         "ls": "bash",
         "list_directory": "bash",
         "search_file_contents": "bash",
         "find_files": "bash",
     },
     EXCLUDED_SUBAGENT_TOOLS: list[str] = ["agent", "subagent", "compact_context"];
def _abs_path(p: any) -> str;

def _parse_scalar(value: str) -> any;
def parse_frontmatter(content: str) -> tuple[dict[str, any], str];
def frontmatter_string(value: any) -> str | None;
def frontmatter_string_list(value: any) -> list[str];
def resolve_jackal_root(agent_dir: str = "") -> str;

def _is_existing_dir(path: str) -> bool;

def _is_agent_md(name: str) -> bool;
def _list_files(directory: str, accept: any) -> list[str];
def load_agent_file(file_path: str, source: str) -> dict[str, any] | None;
def load_agents_from_dir(directory: str, source: str) -> list[dict[str, any]];
def discover_subagent_dirs(cwd: str, agent_dir: str = "") -> dict[str, str];
def load_subagents(cwd: str, agent_dir: str = "") -> dict[str, dict[str, any]];

def _agent_sort_key(agent: dict[str, any]) -> str;
def list_subagents(cwd: str, agent_dir: str = "") -> list[dict[str, any]];
def get_subagent(cwd: str, name: str, agent_dir: str = "") -> dict[str, any] | None;
def load_settings_model_overrides(agent_dir: str = "") -> dict[str, str];
def load_project_model_overrides(cwd: str) -> dict[str, str];
def normalize_allowed_tool_names(tools: list[str] | None) -> set[str] | None;
def filter_tools_for_subagent(
    all_tool_names: list[str], allowed_names: set[str] | None
) -> list[str];
def format_subagent_catalog(cwd: str, agent_dir: str = "") -> str;
