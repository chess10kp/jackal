import os;
import tempfile;
import shutil;

def _escape_xml(s: str) -> str;
def format_skills_for_prompt(skills: list[dict[str, any]]) -> str;
def append_skills_to_prompt(system_prompt: str, skills: list[dict[str, any]]) -> str;
def expand_skill_command(text: str, skills: list[dict[str, any]]) -> str;
def load_skill_by_dir(dir_name: str, package_root: str = "") -> str;
def skill_read_allowlist(skills: list[dict[str, any]]) -> dict[str, list[str]];
