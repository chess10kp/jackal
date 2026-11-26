import sys;
import os;
import queue;
def create_live_shell(term: Terminal | None = None) -> LiveShell;
def boot_tui(term: Terminal | None = None) -> LiveShell;
def tui_step(app: LiveShell, poll_timeout_s: float = 0.04) -> bool;
def shutdown_tui(app: LiveShell);

def run_tui;

with entry:__main__ {
    if not sys.stdin.isatty() or not sys.stdout.isatty() {
        print("jackal tui needs a real TTY.");
        raise SystemExit(1);
    }
    run_tui();
}
