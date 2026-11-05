"""Shared mutable state for the agent session compatibility facade."""

import os;

glob:pub history: list[dict[str, any]] = [],
     show_stats: bool = True,
     model: str = os.environ.get("JACKAL_MODEL", "openrouter/anthropic/claude-sonnet-5"),
     thinking_level: str = "",
     mode: str = "normal",
     _t0: float = 0.0,
     _n_tools: int = 0,
     _model_prefs: dict[str, any] = {},
     _model_prefs_loaded: bool = False;


def:pub set_mode_state(next_mode: str) -> None {
    mode = next_mode;
}

def:pub get_mode_state() -> str {
    return mode;
}

def:pub set_model_state(name: str) -> None {
    model = name;
}

def:pub get_model_state() -> str {
    return model;
}

def:pub set_thinking_level_state(level: str) -> None {
    thinking_level = level;
}

def:pub get_thinking_level_state() -> str {
    return thinking_level;
}

def:pub reset_turn_stats(t0: float) -> None {
    _t0 = t0;
    _n_tools = 0;
}

def:pub bump_tool_count() -> None {
    _n_tools += 1;
}

"""Adopt a successfully loaded model_prefs dict and latch the one-shot."""
def:pub adopt_model_prefs(raw: dict[str, any]) -> None {
    _model_prefs = raw;
    _model_prefs_loaded = True;
}
