"""Native HTTP/1.1 streaming client for OpenAI-compatible SSE responses.

Uses Jac's native socket and TLS floors directly. The response is incremental:
headers are returned as soon as they arrive and `readline` decodes the HTTP
chunk framing while preserving SSE line boundaries.
"""

import from socket { create_connection, socket }
import from ssl { create_default_context, SSLSocket }
import json;


obj HttpStreamResponse {
    has status: int = 0,
        headers: dict[str, str] = {},
        tcp: socket | None = None,
        tls: SSLSocket | None = None,
        buffer: bytes = b"",
        chunked: bool = False,
        chunk_remaining: int = 0,
        content_remaining: int = -1,
        finished: bool = False;

    def read(size: int = -1) -> bytes;
    def readline -> str;
    def close;
    def _recv(size: int) -> bytes;
    def _take_raw(size: int) -> bytes;
    def _read_raw_line -> bytes;
    def _next_chunk -> bool;
}


obj _HttpUrl {
    has scheme: str,
        host: str,
        port: int,
        path: str;
}


def _parse_url(url: str) -> _HttpUrl {
    scheme: str = "https";
    rest: str = url;
    if url.startswith("https://") {
        rest = url[8:];
    } elif url.startswith("http://") {
        scheme = "http";
        rest = url[7:];
    }
    slash = rest.find("/");
    hostport: str = rest if slash < 0 else rest[:slash];
    path: str = "/" if slash < 0 else rest[slash:];
    host: str = hostport;
    port: int = 443 if scheme == "https" else 80;
    colon = hostport.rfind(":");
    if colon >= 0 {
        host = hostport[:colon];
        port = int(hostport[colon + 1:]);
    }
    return _HttpUrl(scheme=scheme, host=host, port=port, path=path);
}


def _find_header_end(raw: bytes) -> int {
    i: int = 0;
    while i + 3 < len(raw) {
        if raw[i] == 13 and raw[i + 1] == 10
            and raw[i + 2] == 13 and raw[i + 3] == 10 {
            return i;
        }
        i += 1;
    }
    return -1;
}


def _request_bytes(
    url: _HttpUrl,
    headers: dict[str, str],
    body: bytes,
) -> bytes {
    lines: list[str] = [
        "POST " + url.path + " HTTP/1.1",
        "Host: " + url.host,
        "Connection: close",
        "Content-Type: application/json",
        "Accept: text/event-stream",
        "Accept-Encoding: identity",
        "Content-Length: " + str(len(body)),
        "User-Agent: jackal-native/1.0",
    ];
    for name in headers {
        lines.append(name + ": " + headers[name]);
    }
    return ("\r\n".join(lines) + "\r\n\r\n").encode("utf-8") + body;
}


def _recv_from(tcp: socket, tls: SSLSocket | None, size: int) -> bytes {
    if tls is not None {
        return tls.recv(size);
    }
    return tcp.recv(size);
}


def _send_to(tcp: socket, tls: SSLSocket | None, data: bytes) {
    if tls is not None {
        tls.sendall(data);
    } else {
        tcp.sendall(data);
    }
}


def _parse_headers(raw: bytes) -> tuple[int, dict[str, str]] {
    text = raw.decode("utf-8", "replace");
    lines = text.split("\r\n");
    status: int = 0;
    if lines {
        parts = lines[0].split(" ");
        if len(parts) > 1 {
            try {
                status = int(parts[1]);
            } except ValueError {
                status = 0;
            }
        }
    }
    headers: dict[str, str] = {};
    for line in lines[1:] {
        colon = line.find(":");
        if colon > 0 {
            headers[line[:colon].strip().lower()] = line[colon + 1:].strip();
        }
    }
    return (status, headers);
}


def post_json_stream(
    url: str,
    headers: dict[str, str],
    body: dict[str, any],
) -> HttpStreamResponse {
    parsed: _HttpUrl = _parse_url(url);
    tcp: socket = create_connection((parsed.host, parsed.port));
    tls: SSLSocket | None = None;
    if parsed.scheme == "https" {
        ctx = create_default_context();
        tls = ctx.wrap_socket(tcp, server_hostname=parsed.host);
    }
    payload = json.dumps(body).encode("utf-8");
    _send_to(tcp, tls, _request_bytes(parsed, headers, payload));

    raw = b"";
    sep: int = -1;
    while sep < 0 {
        piece = _recv_from(tcp, tls, 8192);
        if not piece {
            break;
        }
        raw += piece;
        sep = _find_header_end(raw);
    }
    if sep < 0 {
        if tls is not None { tls.close(); } else { tcp.close(); }
        raise Exception("HTTP response ended before headers");
    }
    (status, response_headers) = _parse_headers(raw[:sep]);
    transfer: str = response_headers.get("transfer-encoding", "").lower();
    length: int = -1;
    try {
        length = int(response_headers.get("content-length", "-1"));
    } except ValueError {
        length = -1;
    }
    return HttpStreamResponse(
        status=status,
        headers=response_headers,
        tcp=tcp,
        tls=tls,
        buffer=raw[sep + 4:],
        chunked=transfer.find("chunked") >= 0,
        content_remaining=length,
    );
}


impl HttpStreamResponse._recv(size: int) -> bytes {
    if self.tls is not None {
        return self.tls.recv(size);
    }
    if self.tcp is not None {
        return self.tcp.recv(size);
    }
    return b"";
}


impl HttpStreamResponse._take_raw(size: int) -> bytes {
    out = b"";
    while len(out) < size {
        if self.buffer {
            take = min(size - len(out), len(self.buffer));
            out += self.buffer[:take];
            self.buffer = self.buffer[take:];
            continue;
        }
        piece = self._recv(max(8192, size - len(out)));
        if not piece {
            break;
        }
        self.buffer = piece;
    }
    return out;
}


impl HttpStreamResponse._read_raw_line -> bytes {
    line = b"";
    while True {
        ch = self._take_raw(1);
        if not ch {
            break;
        }
        line += ch;
        if ch == b"\n" {
            break;
        }
    }
    return line;
}


impl HttpStreamResponse._next_chunk -> bool {
    line = self._read_raw_line().decode("ascii", "replace").strip();
    if not line {
        self.finished = True;
        return False;
    }
    semicolon = line.find(";");
    size_text = line[:semicolon] if semicolon >= 0 else line;
    try {
        self.chunk_remaining = int(size_text, 16);
    } except ValueError {
        self.finished = True;
        return False;
    }
    if self.chunk_remaining > 0 {
        return True;
    }
    trailer: bytes = self._read_raw_line();
    while trailer not in [b"\r\n", b"\n", b""] {
        trailer = self._read_raw_line();
    }
    self.finished = True;
    return False;
}


impl HttpStreamResponse.read(size: int = -1) -> bytes {
    out = b"";
    wanted = size if size >= 0 else -1;
    while not self.finished and (wanted < 0 or len(out) < wanted) {
        if self.chunked {
            if self.chunk_remaining == 0 and not self._next_chunk() {
                break;
            }
            count = self.chunk_remaining if wanted < 0
                else min(self.chunk_remaining, wanted - len(out));
            piece = self._take_raw(count);
            if not piece {
                self.finished = True;
                break;
            }
            out += piece;
            self.chunk_remaining -= len(piece);
            if self.chunk_remaining == 0 {
                self._take_raw(2);
            }
            continue;
        }
        if self.content_remaining == 0 {
            self.finished = True;
            break;
        }
        count = 8192 if wanted < 0 else wanted - len(out);
        if self.content_remaining >= 0 {
            count = min(count, self.content_remaining);
        }
        piece = self._take_raw(count);
        if not piece {
            self.finished = True;
            break;
        }
        out += piece;
        if self.content_remaining >= 0 {
            self.content_remaining -= len(piece);
        }
    }
    return out;
}


impl HttpStreamResponse.readline -> str {
    line = "";
    while not self.finished {
        ch = self.read(1);
        if not ch {
            break;
        }
        line += ch.decode("utf-8", "replace");
        if ch == b"\n" {
            break;
        }
    }
    return line;
}


impl HttpStreamResponse.close {
    if self.tls is not None {
        self.tls.close();
        self.tls = None;
    } elif self.tcp is not None {
        self.tcp.close();
        self.tcp = None;
    }
    self.finished = True;
}
