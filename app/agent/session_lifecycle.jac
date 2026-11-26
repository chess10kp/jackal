import os;
import time;

def extensions_status -> ExtensionStatus;
def _warm_sidecar(base_cwd: str);
def session_boot(
    sid: str = "",
    cwd: str = "",
    decls: list[any] | None = None,
    wait_budget_s: float = 5.0,
    interactive_ui: bool = False,
) -> ExtensionStatus;
def wait_extensions_ready(timeout_s: float = -1.0) -> ExtensionStatus;
def enqueue_prompt(message: str) -> int;

def drain_prompt_queue -> list[str];

def session_dispose;
