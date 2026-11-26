import os;
import re;
def list_chain_files(dir_path: str) -> list[str];
def parse_step_body(agent: str, section_body: str) -> dict[str, any];
def parse_chain_markdown(content: str, source: str, file_path: str) -> dict[str, any];
def load_chains_from_dir(dir_path: str, source: str) -> list[dict[str, any]];
def discover_chain_dirs(cwd: str, agent_dir: str = "") -> dict[str, str];
def load_chains(cwd: str, agent_dir: str = "") -> dict[str, dict[str, any]];

def _chain_sort_key(chain: dict[str, any]) -> str;
def list_chains(cwd: str, agent_dir: str = "") -> list[dict[str, any]];
def get_chain(cwd: str, name: str, agent_dir: str = "") -> dict[str, any] | None;
def format_chain_catalog(cwd: str, agent_dir: str = "") -> str;
def chain_dirs_exist(cwd: str, agent_dir: str = "") -> bool;
