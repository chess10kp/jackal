import http.server;
import from http.server { ThreadingHTTPServer }
import threading;

glob _sse_mode: list[str] = ["ok"],
     _sse_posts: list[int] = [0];

class _SSEHandler(http.server.BaseHTTPRequestHandler) {
    def do_POST;

    override def log_message(format: str, *args: any);
}

def make_sse_server(mode: str = "ok") -> ThreadingHTTPServer;
