impl responses_body(
    model: str, thinking: str, messages: list[dict[str, any]], tools: list[dict[str, any]]
) -> dict[str, any] {
    inputs: list[dict[str, any]] = [];
    for message in messages {
        role = str(message.get("role", "user"));
        if role == "tool" {
            inputs.append({
                "type": "function_call_output",
                "call_id": message.get("tool_call_id", ""),
                "output": str(message.get("content", "")),
            });
            continue;
        }
        content: any = message.get("content");
        if isinstance(content, str) and content {
            inputs.append({"role": role, "content": content});
        } elif isinstance(content, list) {
            blocks: list[dict[str, any]] = [];
            for block in content {
                if block.get("type") == "text" {
                    blocks.append({
                        "type": "output_text" if role == "assistant" else "input_text",
                        "text": block.get("text", ""),
                    });
                } elif block.get("type") == "image_url" {
                    image: any = block.get("image_url", {});
                    blocks.append({"type": "input_image", "image_url": image.get("url", "")});
                } else {
                    raise ValueError("Unsupported message content for ChatGPT");
                }
            }
            if blocks {
                inputs.append({"role": role, "content": blocks});
            }
        }
        for call in message.get("tool_calls", []) {
            function: dict[str, any] = call.get("function", {});
            inputs.append({
                "type": "function_call",
                "call_id": call.get("id", ""),
                "name": function.get("name", ""),
                "arguments": function.get("arguments", "{}"),
            });
        }
    }
    body: dict[str, any] = {"model": model, "input": inputs, "stream": True, "store": False};
    definitions: list[dict[str, any]] = [];
    for tool in tools {
        function: dict[str, any] = tool.get("function", {});
        definitions.append({
            "type": "function",
            "name": function.get("name", ""),
            "description": function.get("description", ""),
            "parameters": function.get("parameters", {}),
            "strict": False,
        });
    }
    if definitions {
        body["tools"] = definitions;
    }
    if thinking and thinking != "off" {
        body["reasoning"] = {"effort": thinking};
    }
    return body;
}

impl normalize_response(event: dict[str, any], state: dict[str, any]) -> dict[str, any] {
    kind = str(event.get("type", ""));
    if kind in ["response.output_text.delta", "response.refusal.delta"] {
        return {"content": str(event.get("delta", ""))};
    }
    if kind == "response.output_item.done" {
        item: any = event.get("item", {});
        if item.get("type") == "function_call" {
            calls: any = state["calls"];
            calls.append({
                "id": str(item.get("call_id", "")),
                "type": "function",
                "function": {
                    "name": str(item.get("name", "")),
                    "arguments": str(item.get("arguments", "")),
                },
            });
        }
    }
    if kind == "response.completed" {
        response: any = event.get("response", {});
        if response.get("status") != "completed" {
            state["failed"] = True;
            return {"error": "ChatGPT response did not complete"};
        }
        state["completed"] = True;
    }
    if kind in ["response.failed", "response.incomplete", "error"] {
        state["failed"] = True;
        return {
            "error": "ChatGPT response failed or was incomplete; check account usage and retry",
        };
    }
    return {};
}

impl consume_responses(lines: any) -> Iterator[dict[str, any]] {
    state: dict[str, any] = {"calls": [], "completed": False, "failed": False};
    data: list[str] = [];
    try {
        for raw in lines {
            line = raw.decode("utf-8").rstrip("\r\n");
            if line.startswith("data:") {
                data.append(line[5:].lstrip(" "));
            } elif not line and data {
                payload = "\n".join(data);
                data.clear();
                if payload == "[DONE]" {
                    break;
                }
                event: any = json.loads(payload);
                if not isinstance(event, dict) {
                    raise ValueError("Invalid ChatGPT event");
                }
                chunk = normalize_response(event, state);
                if chunk {
                    yield chunk;
                }
                if state["failed"] {
                    return;
                }
                if state["completed"] {
                    break;
                }
            }
        }
        if not state["completed"] {
            yield {
                "error": "ChatGPT stream ended before completion; partial output was not accepted",
            };
        } elif state["calls"] {
            yield {"tool_calls": state["calls"]};
        }
    } except Exception {
        yield {"error": "ChatGPT returned an invalid or interrupted response stream"};
    }
}

impl responses_stream(
    model: str,
    thinking: str,
    messages: list[dict[str, any]],
    tools: list[dict[str, any]],
    transport: any,
    account_key: str = "",
) -> Iterator[dict[str, any]] {
    try {
        body = responses_body(model, thinking, messages, tools);
        req = urllib.request.Request(
            "https://api.openai.com/v1/responses",
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
                "Authorization": "Bearer " + access_token(account_key),
            },
        );
        with urllib.request.urlopen(req, timeout=90.0) as response {
            transport._notify_response(int(response.status), dict(response.headers));
            yield from consume_responses(response);
        }
    } except urllib.error.HTTPError as error {
        transport._notify_response(int(error.code), dict(error.headers));
        yield {
            "error": "ChatGPT request failed (HTTP "
                + str(error.code)
                + "); check authorization and account usage",
        };
    } except Exception {
        yield {"error": "ChatGPT request failed; check /login openai and network access"};
    }
}
