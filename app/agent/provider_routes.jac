"""Shared provider routing and model catalog data.

Kept independent from the LLM transport so native consumers such as the
model catalog do not import the server-facing streaming implementation.
"""

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
