import threading as _threading
from http.server import BaseHTTPRequestHandler as _BaseHTTPRequestHandler, HTTPServer as _HTTPServer


class _SSEHandler(_BaseHTTPRequestHandler):
    mode = "ok"

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)
        self.posts[0] += 1
        if self.mode == "flaky" and self.posts[0] == 1:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"flaky upstream")
            self.wfile.flush()
            return
        if self.mode == "boom":
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"upstream down")
            self.wfile.flush()
            return
        # "ok", or "flaky" past its first failed post: stream normally
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.wfile.write(b'data: {"choices":[{"delta":{"content":"hello"}}]}\n\n')
        self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def log_message(self, format, *args):
        pass


def make_sse_server(mode="ok"):
    """Threaded local SSE (or error) endpoint for transport tests.

    mode="flaky": first POST answers 503, subsequent POSTs stream normally —
    used to prove after_provider_response fires once per provider attempt."""
    handler = type("H", (_SSEHandler,), {"mode": mode, "posts": [0]})
    srv = _HTTPServer(("127.0.0.1", 0), handler)
    _threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv
