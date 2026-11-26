glob model: str = get_model_state(),
     thinking_level: str = get_thinking_level_state();
def set_model(name: str) -> str;

def set_thinking_level(level: str) -> str;

def get_model -> str;
def restore_model(name: str) -> str;

def get_thinking_level -> str;
