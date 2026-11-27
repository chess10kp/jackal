import os;
import json;

glob _hydrated_envs: set[str] = set();

def _key_env(provider_id: str) -> str;

glob _ROUTE_STORED_ALIASES: dict[str, list[str]] = {"openai_compat": ["openai"]};

glob _PI_EXTRA_KEY_ENVS: dict[str, str] = {
    "anthropic": "ANTHROPIC_API_KEY",
    "google": "GOOGLE_API_KEY",
    "gemini": "GEMINI_API_KEY",
    "xai": "XAI_API_KEY",
    "mistral": "MISTRAL_API_KEY",
    "groq": "GROQ_API_KEY",
};

def _stored_key_for_route(stored: dict[str, any], route_id: str) -> str;

def _models_json_openai_base(path: str) -> str;

def apply_pi_models_environment;
def hydrate_auth_environment -> list[str];
def note_hydrated(key_env: str);
def logout_provider(provider_id: str) -> str;
def stored_providers -> list[str];
