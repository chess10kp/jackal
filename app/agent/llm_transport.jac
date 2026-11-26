import os;
import json;
import time;
import urllib.request;
import urllib.error;

obj Transport {
    has base_url: str = "https://api.openai.com/v1",
        api_key: str = "",
        model: str = "",
        thinking: str = "";

    has hook_bridge: any = None,
        hook_timeout: float = 2.0;

    def _build_body(
        messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
    ) -> dict[str, any];

    def stream(
        messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
    ) -> Iterator[dict[str, any]];
    def _notify_response(status: int, headers: dict[str, str]);
    def _open_stream(
        url: str, headers: dict[str, str], body: dict[str, any]
    ) -> Iterator[dict[str, any]];
}

glob _mock_cursor: dict[str, int] = {};

def _mock_last_user(messages: list[dict[str, any]]) -> str;

def _mock_next_response(script_path: str) -> dict[str, any] | None;

obj MockTransport(Transport) {
    override def stream(
        messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
    ) -> Iterator[dict[str, any]];
}

glob PROVIDER_ROUTES: dict[str, dict[str, any]] = {
    "openai": {
        "description": "Continue with ChatGPT",
        "base_url": "https://api.openai.com/v1",
        "base_url_env": "",
        "key_env": "",
        "authType": "oauth",
        "models": [],
    },
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
def provider_for(model: str) -> str;
def routed_model_id(provider: str, name: str) -> str;
def credential_error(model: str) -> str;
def make_transport(model: str = "", thinking: str = "", hook_bridge: any = None) -> Transport;

obj ProviderTransport(Transport) {
    has ext_bridge: any = None,
        ext_cfg: dict[str, any] = {};

    override def stream(
        messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
    ) -> Iterator[dict[str, any]];
}

def make_ext_transport(
    bridge: PluginBridge | None, model_id: str, thinking: str = ""
) -> ProviderTransport | None;

obj ChatGPTTransport(Transport) {
    has account_key: str = "";
    override def stream(
        messages: list[dict[str, any]], tool_defs: list[dict[str, any]]
    ) -> Iterator[dict[str, any]];
}
