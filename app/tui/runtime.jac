import threading;
import queue;

def _apply_resize(app: LiveShell, columns: int, rows: int);
def _begin_assistant_reply(app: LiveShell, user_text: str, model_text: str = "");

def _finish_stream(app: LiveShell, final_body: str);

def _tick_stream(app: LiveShell);

def _accept_approval(app: LiveShell);

def _reject_approval(app: LiveShell);
