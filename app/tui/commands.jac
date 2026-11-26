import os;
import threading;
import queue;
def _resume_session(app: LiveShell, sid: str) -> str;
def _run_slash(app: LiveShell, line: str) -> str;
def _ui_open_modal(app: LiveShell, rec: dict[str, any]) -> bool;
def _ui_settle(app: LiveShell, value: any, use_cancel: bool = False);
def _run_ext_command_async(app: LiveShell, name: str, args: str) -> str;

def _handle_ui_modal_key(app: LiveShell, key: str);
def _tick_ui_modal(app: LiveShell);
def _mcp_current_specs -> dict[str, list[str]];

def _mcp_window_refresh(app: LiveShell, win: any);

def _mcp_window_action(app: LiveShell, win: any, action: str) -> str;
def _open_mcp_window(app: LiveShell) -> str;
