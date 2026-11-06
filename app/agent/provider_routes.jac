"""Shared provider routing and model catalog data.

Kept independent from the LLM transport so native consumers such as the
model catalog do not import the server-facing streaming implementation.
"""

import os;

glob:pub PROVIDER_ROUTES: dict[str, dict[str, any]] = {
    "openrouter": {
        "description": "OpenRouter multi-provider gateway",
        "base_url": "https://openrouter.ai/api/v1",
        "base_url_env": "",
        "key_env": "OPENROUTER_API_KEY",
        "models": ["anthropic/claude-sonnet-5", "openai/gpt-5"],
    },
    "deepseek": {
        "description": "DeepSeek API",
        "base_url": "https://api.deepseek.com/v1",
        "base_url_env": "",
        "key_env": "DEEPSEEK_API_KEY",
        "models": ["deepseek-chat", "deepseek-reasoner"],
    },
    "zai": {
        "description": "Z.ai GLM models (OpenAI-compatible)",
        "base_url": "https://api.z.ai/api/paas/v4",
        "base_url_env": "",
        "key_env": "ZAI_API_KEY",
        "models": ["glm-4.6", "glm-4.5", "glm-4.5-air"],
    },
    "openai_compat": {
        "description": "Any OpenAI-compatible chat-completions endpoint",
        "base_url": "https://api.openai.com/v1",
        "base_url_env": "OPENAI_COMPAT_BASE",
        "key_env": "OPENAI_API_KEY",
        "models": ["gpt-4o", "gpt-4o-mini"],
    },
    "mock": {
        "description": "Local mockllm (no network, no credential)",
        "base_url": "local://mockllm",
        "base_url_env": "",
        "key_env": "",
        "models": ["mock"],
    },
};

# Dict key iteration and lookup currently lower poorly when the mapped value is
# a nested dynamic dict. Keep the stable provider key set explicitly typed for
# native consumers that enumerate credential and model routes.
glob:pub PROVIDER_IDS: list[str] = [
    "openrouter", "deepseek", "zai", "openai_compat", "mock",
];


"""Map a model id to its provider id (pure, prefix-based dispatch)."""
def:pub provider_for(model: str) -> str {
    if model.startswith("openrouter/") { return "openrouter"; }
    if model.startswith("deepseek/") { return "deepseek"; }
    if model.startswith("zai/") { return "zai"; }
    if model == "mock" or model == "mockllm" or model.startswith("mock/") {
        return "mock";
    }
    if model.startswith("ext/") { return "ext"; }
    return "openai_compat";
}


"""Return the actionable missing-credential message, or empty when usable."""
def:pub credential_error(model: str) -> str {
    try {
        provider: str = provider_for(model);
        if provider == "ext" { return ""; }
        key_env: str = "";
        if provider == "openrouter" { key_env = "OPENROUTER_API_KEY"; }
        if provider == "deepseek" { key_env = "DEEPSEEK_API_KEY"; }
        if provider == "zai" { key_env = "ZAI_API_KEY"; }
        if provider == "openai_compat" { key_env = "OPENAI_API_KEY"; }
        if not key_env { return ""; }
        if os.getenv(key_env, "") { return ""; }
        fix: str = "set " + key_env;
        if provider == "openai_compat" {
            fix += " (or point OPENAI_COMPAT_BASE at your endpoint)";
        }
        return (
            "model \"" + model + "\" routes via " + provider + " — " + fix
            + " or pick another provider (/model for options)."
        );
    } except Exception {
        return "";
    }
}
