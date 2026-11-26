import os;
import json;
import time;
import shutil;
import tempfile;

glob _HARNESS_ENV_KEYS: list[str] = [
    "JACKAL_MODEL",
    "JACKAL_MOCK_SCRIPT",
    "JACKAL_MOCK_LOG",
    "JACKAL_AGENT_DIR",
    "JACKAL_MODE",
    "OPENROUTER_API_KEY",
    "OPENAI_API_KEY",
    "DEEPSEEK_API_KEY",
    "ZAI_API_KEY",
];

obj TuiHarness {
    has app: LiveShell,
        term: EmulatedTerminal,
        base_dir: str = "",
        project: str = "",
        log_path: str = "",
        script_path: str = "",
        saved_cwd: str = "",
        saved_env: dict[str, any] = {},
        closed: bool = False;
    def step(n: int = 1);
    def type_text(text: str);
    def press(key: str);

    def paste(text: str);

    def resize(columns: int, rows: int);

    def screen -> str;
    def wait_for(needle: str, timeout_s: float = 30.0) -> str;
    def wait_gone(needle: str, timeout_s: float = 30.0);
    def wait_idle(timeout_s: float = 30.0);
    def calls -> list[dict[str, any]];

    def read(rel: str) -> str;

    def exists(rel: str) -> bool;
    def dump -> str;

    def close;
}

def open_tui(
    columns: int = 100,
    rows: int = 30,
    files: dict[str, str] | None = None,
    script: list[dict[str, any]] | None = None,
    mode: str = "normal",
) -> TuiHarness;
