impl set_mode_state(next_mode: str) {
    mode = next_mode;
}

impl get_mode_state -> str {
    return mode;
}

impl set_model_state(name: str) {
    model = name;
}

impl get_model_state -> str {
    return model;
}

impl set_thinking_level_state(level: str) {
    thinking_level = level;
}

impl get_thinking_level_state -> str {
    return thinking_level;
}

impl reset_turn_stats(t0: float) {
    _t0 = t0;
    _n_tools = 0;
}

impl bump_tool_count {
    _n_tools += 1;
}

impl adopt_model_prefs(raw: dict[str, any]) {
    _model_prefs = raw;
    _model_prefs_loaded = True;
}
