import from .openai_responses { responses_body, normalize_response, consume_responses }

test "Responses carries prior tool calls and outputs without server storage" {
    messages: list[dict[str, any]] = [
        {"role": "system", "content": "instructions"},
        {"role": "user", "content": "read the file"},
        {
            "role": "assistant",
            "content": None,
            "tool_calls": [{"id": "call_1", "function": {"name": "read", "arguments": "{}"}}],
        },
        {"role": "tool", "tool_call_id": "call_1", "content": "file content"},
        {"role": "user", "content": "continue"},
    ];
    tools: list[dict[str, any]] = [
        {"type": "function", "function": {"name": "read", "parameters": {"type": "object"}}},
    ];
    body = responses_body("model-slug", "high", messages, tools);
    assert body["store"] is False
        and body["stream"] is True, "account calls require streaming and disable storage";
    assert body["input"][2]["type"] == "function_call", "call history is retained";
    assert body["input"][3]["call_id"] == "call_1", "output references original call";
    assert body["tools"][0]["name"] == "read", "tools use Responses shape";
    assert body["model"] == "model-slug", "use the account catalog slug";
}

test "partial text and pending tool calls require terminal success" {
    state: dict[str, any] = {"calls": [], "completed": False, "failed": False};
    text = normalize_response({"type": "response.output_text.delta", "delta": "partial"}, state);
    assert text["content"] == "partial", "text can stream immediately";
    result = normalize_response(
        {
            "type": "response.output_item.done",
            "item": {"type": "function_call", "call_id": "id", "name": "bash", "arguments": "{}"},
        },
        state,
    );
    assert not result and not state["completed"], "tool calls wait for terminal event";
    result = normalize_response({"type": "response.incomplete"}, state);
    assert result.get("error")
        and state["failed"]
        and not state["completed"], "failure after text cannot be accepted as success";
    state = {"calls": [], "completed": False, "failed": False};
    normalize_response({"type": "response.completed", "response": {"status": "completed"}}, state);
    assert state["completed"] and not state["failed"], "terminal success is explicit";
}

test "SSE truncation and failure never release buffered tool calls" {
    call = b'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"id","name":"bash","arguments":"{}"}}\n';
    for ending in [b'data: [DONE]\n', b'data: {"type":"response.failed"}\n', b'data: malformed\n'] {
        lines: list[bytes] = [call, b"\n", ending, b"\n"];
        chunks: list[dict[str, any]] = list(consume_responses(lines));
        assert len(chunks) == 1 and chunks[0].get("error"), "unfinished calls cannot execute";
    }
    success: list[bytes] = [
        call,
        b"\n",
        b'data: {"type":"response.completed","response":{"status":"completed"}}\n',
        b"\n",
    ];
    chunks: list[dict[str, any]] = list(consume_responses(success));
    assert len(chunks) == 1
        and len(chunks[0]["tool_calls"]) == 1, "successful call is released exactly once";
}
