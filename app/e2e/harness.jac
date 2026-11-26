import os;
import sys;
import json;
import shutil;
import tempfile;
import subprocess;
import time;
import threading;
import codecs;
import pty;
import fcntl;
import termios;
import struct;

glob E2E_TIMEOUT_S: int = 300;
def app_dir -> str;

def jac_bin -> str;
def native_bin(entry_mod: str) -> str;

glob _built_bins: list[str] = [];

obj Sandbox {
    has base_dir: str = "",
        project: str = "",
        agent_dir: str = "",
        script_path: str = "",
        log_path: str = "";

    def write(rel: str, text: str);

    def read(rel: str) -> str;

    def exists(rel: str) -> bool;
    def script(steps: list[dict[str, any]]);
    def calls -> list[dict[str, any]];

    def cleanup;
    def explain(r: any) -> str;
}

def make_sandbox(files: dict[str, str] | None = None) -> Sandbox;

obj RunResult {
    has code: int = 0,
        stdout: str = "",
        stderr: str = "";
    def events -> list[dict[str, any]];

    def event_types -> list[str];

    def describe -> str;
}

def run_jackal(
    sb: Sandbox,
    args: list[str],
    stdin_text: str = "",
    env_extra: dict[str, str] | None = None,
    timeout_s: int = E2E_TIMEOUT_S,
) -> RunResult;
def jsonl(kind: str, text: str = "", extra: dict[str, any] | None = None) -> str;

glob KEYS: dict[str, str] = {
    "enter": "\r",
    "esc": "\x1b",
    "tab": "\t",
    "backspace": "\x7f",
    "up": "\x1b[A",
    "down": "\x1b[B",
    "right": "\x1b[C",
    "left": "\x1b[D",
    "shift+tab": "\x1b[Z",
    "ctrl+c": "\x03",
    "ctrl+d": "\x04",
};

obj TuiSession {
    has proc: any = None,
        master_fd: int = -1,
        screen: EmulatedTerminal | None = None,
        raw: list[str] = [],
        lock: any = None,
        reader: any = None,
        alive: bool = True;

    def _read_loop;

    def send(data: str);
    def type_text(text: str, delay_s: float = 0.005);

    def press(key: str);

    def screen_text -> str;

    def raw_output -> str;
    def wait_for(needle: str, timeout_s: float = 60.0) -> str;
    def wait_gone(needle: str, timeout_s: float = 30.0) -> str;
    def wait_exit(timeout_s: float = 30.0) -> int | None;

    def close;
}

def spawn_tui(
    sb: Sandbox,
    cols: int = 100,
    rows: int = 30,
    env_extra: dict[str, str] | None = None,
    boot_timeout_s: float = 240.0,
) -> TuiSession;
def fixture_path(name: str) -> str;
def write_project_config(sb: Sandbox, cfg: dict[str, any]);
