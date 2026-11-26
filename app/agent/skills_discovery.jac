import os;
def _load_skills_from_dir(
    dir_path: str,
    source: str,
    include_root_files: bool = True,
    ignore_rules: list[str] | None = None,
    root_dir: str = "",
) -> dict[str, list[dict[str, any]]];
def load_skills_from_dir(dir_path: str, source: str) -> dict[str, list[dict[str, any]]];
def _find_project_skills_dir(cwd: str) -> str;

def _normalize_path(p: str) -> str;

def _resolve_skill_path(p: str, cwd: str) -> str;

def _path_under(target: str, base_root: str) -> bool;

def _get_source(rp: str, user_dir: str, proj_dir: str) -> str;
def _add_loaded(
    result: dict[str, list[dict[str, any]]],
    skill_map: dict[str, dict[str, any]],
    real_paths: set[str],
    all_diags: list[dict[str, any]],
    collision_diags: list[dict[str, any]],
);

def _resolve_package_root -> str;

def _skill_sort_key(skill: dict[str, any]) -> str;
def load_jackal_skills(
    cwd: str = "",
    package_root: str = "",
    agent_dir: str = "",
    skill_paths: list[str] | None = None,
    include_defaults: bool = True,
) -> dict[str, list[dict[str, any]]];
