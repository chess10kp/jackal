"""Shared state and pure shell values for the native Jackal TUI."""

import threading;
import from tui.message_queue { MessageQueue }
import from ui.runtime { UiSession }
import from ui.screen { ShellScreen }
import from ui.transcript { TranscriptProjection, TranscriptMessage }
import from ui.renderer { Renderer }
import from ui.terminal { Terminal }
import from ui.input { InputNormalizer }
import from tui.window { WindowState }

# /explorer walk bounds + skip list (dot-dirs are always skipped; dot-FILES
# stay selectable). Caps keep huge trees responsive inside an 8-row overlay.
glob:pub _EXPLORER_SKIP_DIRS: list[str] = [
         "node_modules", "__pycache__", ".git", ".jac", ".jackal",
         ".venv", "venv", ".mypy_cache", ".pytest_cache",
     ],
     _EXPLORER_MAX_FILES: int = 400,
     _EXPLORER_MAX_DEPTH: int = 6;

# Whitespace paths: @"quoted path.md" / @"quoted path.md":10-20 are
# handled by a thin TUI-side pre-pass (_take_quoted_mentions below). The
# real fix belongs in agent.context_input (its _FILE_MENTION_PATTERN
# splits on whitespace and cannot learn quoting) — that file is outside
# this shell's ownership, so the pre-pass lives here until then.
# Quoted mention: @"path" / @"path:N[-M]" / @"path":N[-M] — an optional
# line range is accepted inside OR after the closing quote.
glob:pub _QUOTED_MENTION_PATTERN: str = r'@"([^"]+)"(?::(\d+)(?:-(\d+))?)?';

# Built-in slash commands handled by _run_slash locally (name without the
# leading "/" -> short description shown by /help).
glob:pub SLASH_BUILTINS: dict[str, str] = {
    "exit": "quit jackal",
    "quit": "quit jackal",
    "help": "list commands",
    "clear": "clear conversation history (starts a new session)",
    "new": "start a new session",
    "compact": "summarize older history to free context",
    "context": "show context-window usage",
    "mode": "show or set dev mode (normal|auto-accept|yolo|plan|ask)",
    "logout": "remove a stored provider credential",
    "abort": "abort the active turn",
    "login": "configure provider authentication",
    "sessions": "list saved sessions",
    "resume": "resume a saved session",
    "export": "export transcript to markdown",
    "model": "show or set the model",
    "commands": "list extension commands",
    "shortcuts": "list extension shortcuts",
    "tasks": "list project tasks",
    "checkpoint": "create a checkpoint (/checkpoint NAME)",
    "checkpoints": "browse and restore checkpoints",
    "explorer": "multi-select files as @mentions",
    "mcp": "show MCP server status (/mcp restart NAME)",
    "skills": "list available skills (/skill:name)",
};


obj:pub LiveShell {
    has session: UiSession,
        shell: ShellScreen,
        proj: TranscriptProjection,
        renderer: Renderer,
        term: Terminal,
        normalizer: InputNormalizer,
        messages: list[TranscriptMessage] = [],
        rev: int = 0,
        msg_n: int = 0,
        phase: str = "ready",
        stream_full: str = "",
        stream_shown: int = 0,
        stream_msg_id: str = "",
        stream_tick: int = 0,
        spin_i: int = 0,
        running: bool = True,
        dirty: bool = True,
        columns: int = 80,
        rows: int = 24,
        evq: (MessageQueue | None) = None,
        worker: (threading.Thread | None) = None,
        tool_msg_id: str = "",
        appr_event: (threading.Event | None) = None,
        appr_approved: bool = False,
        # Window stack (tui/window.jac API): top entry owns keys; picker
        # entries render above the prompt, other modal windows use overlay.
        windows: list[WindowState] = [],
        mode: str = "normal",
        cmd_q: (MessageQueue | None) = None,
        auth_flow: dict[str, any] = {},
        auth_data: dict[str, any] = {},
        slash_sel: int = 0,
        slash_dismissed: str = "";
}

# Picker rows come from agent.llm PROVIDER_ROUTES (one header per provider
# followed by its advertised models) plus each provider's last-used model
# from agent.session model_preferences(). Header rows carry the sentinel id
# __header__ and are skipped on enter.
