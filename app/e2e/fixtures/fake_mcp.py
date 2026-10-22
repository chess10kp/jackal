"""Minimal stdio MCP server for e2e tests (newline-delimited JSON-RPC).

Tools: echo(text) -> "echo: <text>", add(a, b) -> sum. Set FAKE_MCP_FAIL=1 to
exit immediately (spawn-failure path).
"""
import json
import os
import sys

if os.environ.get("FAKE_MCP_FAIL"):
    sys.exit(3)

TOOLS = [
    {"name": "echo", "description": "Echo text back.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
    {"name": "add", "description": "Add two numbers.",
     "inputSchema": {"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}, "required": ["a", "b"]}},
    {"name": "where", "description": "Report the server process working directory.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {"name": "envpeek", "description": "Report FAKE_MCP_TOKEN from the server environment.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {"name": "die", "description": "Reply once, then exit the server process.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
]


def reply(req_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    req = json.loads(line)
    method = req.get("method")
    rid = req.get("id")
    if rid is None:
        continue  # notification
    if method == "initialize":
        reply(rid, {"protocolVersion": req["params"].get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {}}, "serverInfo": {"name": "fake", "version": "0"}})
    elif method == "tools/list":
        reply(rid, {"tools": TOOLS})
    elif method == "prompts/list":
        reply(rid, {"prompts": [{"name": "greet", "description": "Greet someone.",
                                 "arguments": [{"name": "who"}]}]})
    elif method == "prompts/get":
        who = req["params"].get("arguments", {}).get("who", "world")
        reply(rid, {"description": "A greeting",
                    "messages": [{"role": "user",
                                  "content": {"type": "text", "text": "Hello, " + str(who) + "!"}}]})
    elif method == "tools/call":
        name = req["params"]["name"]
        args = req["params"].get("arguments", {})
        if name == "echo":
            text = "echo: " + str(args.get("text", ""))
        elif name == "add":
            text = str(args.get("a", 0) + args.get("b", 0))
        elif name == "where":
            text = os.getcwd()
        elif name == "envpeek":
            text = "token=" + os.environ.get("FAKE_MCP_TOKEN", "unset")
        elif name == "die":
            reply(rid, {"content": [{"type": "text", "text": "dying"}]})
            sys.stdout.flush()
            os._exit(7)
        else:
            reply(rid, {"content": [{"type": "text", "text": "unknown tool"}], "isError": True})
            continue
        reply(rid, {"content": [{"type": "text", "text": text}]})
    else:
        reply(rid, error={"code": -32601, "message": "method not found"})
