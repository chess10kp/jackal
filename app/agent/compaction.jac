import json;
import os;

def _path_abspath(p: str) -> str;

def _path_dirname(p: str) -> str;

glob CHARS_PER_TOKEN: int = 4,
     DEFAULT_CONTEXT_MAX: int = 128000,
     SUMMARY_RESERVE_TOKENS: int = 8192;

glob DEFAULT_AUTO_COMPACT: dict[str, any] = {
    "enabled": True,
    "thresholdPercent": 80,
    "keepTail": 12,
    "notify": True,
    "strategy": "llm",
};

def estimate_tokens(text: str) -> int;

def _message_to_text(message: dict[str, any]) -> str;

def estimate_messages_tokens(messages: list[dict[str, any]]) -> int;

def compute_context_usage(
    messages: list[dict[str, any]], context_max_override: any = None
) -> dict[str, int];
def load_project_config(cwd: str) -> dict[str, any];

def resolve_auto_compact_config(
    raw: dict[str, any] | None = None, compact_strategy: str = ""
) -> dict[str, any];

def should_auto_compact(usage: dict[str, int], config: dict[str, any]) -> bool;

def _extract_content_text(content: any) -> str;

def build_mechanical_summary(messages: list[dict[str, any]]) -> str;

def build_llm_summary_prompt(messages: list[dict[str, any]]) -> str;

def wrap_compaction_summary(text: str) -> str;
def summarize_for_compaction(
    messages: list[dict[str, any]], model_name: str, thinking: str = ""
) -> str | None;
