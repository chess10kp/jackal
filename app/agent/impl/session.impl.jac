impl set_model(name: str) -> str {
    result = _set_model(name);
    if result == name {
        model = name;
    }
    return result;
}

impl set_thinking_level(level: str) -> str {
    result = _set_thinking_level(level);
    if result == level {
        thinking_level = level;
    }
    return result;
}

impl get_model -> str {
    return get_model_state();
}

impl restore_model(name: str) -> str {
    set_model_state(name);
    model = name;
    return name;
}

impl get_thinking_level -> str {
    return get_thinking_level_state();
}
