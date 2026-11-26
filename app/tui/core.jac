def _rule(width: int, ch: str = "─") -> str;

def _pad_to(text: str, width: int) -> str;
def _meter(value: float, width: int) -> str;

def _next_id(app: LiveShell) -> str;

def _commit_messages(app: LiveShell);

def _push_turn(app: LiveShell, role: str, body: str) -> str;

def _rewrite_turn(app: LiveShell, message_id: str, role: str, body: str);
def _finish_turn(app: LiveShell, message_id: str, role: str, body: str);

def _install_layout(app: LiveShell);
def _prompt_prefix(mode: str) -> str;

def _prompt_lines(app: LiveShell) -> list[str];
def _transcript_total_height(app: LiveShell) -> int;
def _scroll_transcript(app: LiveShell, delta: int);
