"""Threaded local SSE (or error) endpoint for transport tests (native port
of the former sse_test_server.py).

mode="flaky": first POST answers 503, subsequent POSTs stream normally —
used to prove after_provider_response fires once per provider attempt.
One server is live at a time (tests run sequentially), so the mode and the
POST counter are module state."""

import http.server;
import from http.server { ThreadingHTTPServer }
import threading;

glob _sse_mode: list[str] = ["ok"],
     _sse_posts: list[int] = [0];

class _SSEHandler(http.server.BaseHTTPRequestHandler) {
    def do_POST {
        length: int = int(self.headers.get("Content-Length", "0"));
        if length {
            self.rfile.read(length);
        }
        _sse_posts[0] += 1;
        mode: str = _sse_mode[0];
        if (mode == "flaky" and _sse_posts[0] == 1) or mode == "boom" {
            self.send_response(503);
            self.end_headers();
            self.wfile.write(b"flaky upstream" if mode == "flaky" else b"upstream down");
            self.wfile.flush();
            return;
        }
        self.send_response(200);
        self.send_header("Content-Type", "text/event-stream");
        self.end_headers();
        self.wfile.write(b'data: {"choices":[{"delta":{"content":"hello"}}]}\n\n');
        self.wfile.flush();
        self.wfile.write(b"data: [DONE]\n\n");
        self.wfile.flush();
    }

    override def log_message(format: str, *args: any) {}
}

def make_sse_server(mode: str = "ok") -> ThreadingHTTPServer {
    _sse_mode[0] = mode;
    _sse_posts[0] = 0;
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _SSEHandler);
    t = threading.Thread(target=srv.serve_forever, args=(0.01,), daemon=True);
    t.start();
    return srv;
}
