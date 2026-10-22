"""Minimal streamable-HTTP MCP server for e2e tests.

Binds an ephemeral port on loopback, prints "READY <port>" to stdout, then
serves POST /mcp: initialize (issues Mcp-Session-Id sess-42; requests after
initialize without it are rejected), notifications -> 202, tools/list (echo)
as JSON, tools/call (echo) as text/event-stream, DELETE -> 204.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

SID = "sess-42"
TOOLS = [
    {"name": "echo", "description": "Echo the given text back.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}},
                     "required": ["text"]}},
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, code, obj, extra=None):
        payload = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        for key, val in (extra or {}).items():
            self.send_header(key, val)
        self.end_headers()
        self.wfile.write(payload)

    def do_DELETE(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length) or b"{}")
        method = req.get("method", "")
        rid = req.get("id")
        if method == "initialize":
            self._json(200, {"jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fake-http", "version": "0"}}},
                {"Mcp-Session-Id": SID})
        elif method.startswith("notifications/"):
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.headers.get("Mcp-Session-Id") != SID:
            self._json(400, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32001, "message": "missing or stale session id"}})
        elif method == "tools/list":
            self._json(200, {"jsonrpc": "2.0", "id": rid, "result": {"tools": TOOLS}})
        elif method == "tools/call":
            name = str(req.get("params", {}).get("name", ""))
            if name != "echo":
                self._json(200, {"jsonrpc": "2.0", "id": rid, "error": {
                    "code": -32601, "message": "unknown tool: " + name}})
                return
            text = str(req.get("params", {}).get("arguments", {}).get("text", ""))
            body = {"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": "echo:" + text}],
                "isError": False}}
            payload = json.dumps(body)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.write(("event: message\ndata: " + payload + "\n\n").encode())
        else:
            self._json(200, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601, "message": "method not found"}})


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print("READY %d" % server.server_address[1], flush=True)
    server.serve_forever()
