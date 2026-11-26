impl _SSEHandler.do_POST {
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

impl _SSEHandler.log_message(format: str, *args: any) {}

impl make_sse_server(mode: str = "ok") -> ThreadingHTTPServer {
    _sse_mode[0] = mode;
    _sse_posts[0] = 0;
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _SSEHandler);
    t = threading.Thread(target=srv.serve_forever, args=(0.01,), daemon=True);
    t.start();
    return srv;
}
