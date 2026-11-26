import json;
import urllib.request;
import urllib.error;

def responses_body(
    model: str, thinking: str, messages: list[dict[str, any]], tools: list[dict[str, any]]
) -> dict[str, any];

def normalize_response(event: dict[str, any], state: dict[str, any]) -> dict[str, any];

def responses_stream(
    model: str,
    thinking: str,
    messages: list[dict[str, any]],
    tools: list[dict[str, any]],
    transport: any,
    account_key: str = "",
) -> Iterator[dict[str, any]];

def consume_responses(lines: any) -> Iterator[dict[str, any]];
