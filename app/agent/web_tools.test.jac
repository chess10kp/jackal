"""Tests for agent/web_tools.jac — same-stem annex (plugin_hooks_events
pattern; the base module carries the shared imports).

Offline-first: URL validation, truncation, and HTML stripping are pure.
The HTTP round-trip test serves canned HTML from a raw-socket server bound
to 127.0.0.1:0 in a daemon thread. The live DuckDuckGo test skips when
JACKAL_SKIP_NET_TESTS=1 or a 3s TCP probe to the search host fails, so CI
never depends on egress.
"""


def _canned_page() -> str {
    parts: list[str] = [];
    parts.append("<html><head><title>Canned Page</title>");
    parts.append("<style>p { color: red; } .x { display: none; }</style>");
    parts.append("</head><body>");
    parts.append("<script>alert('should-not-appear')</script>");
    parts.append("<!-- comment should-not-appear -->");
    parts.append("<h1>Hello</h1><p>World &amp; friends</p>");
    parts.append("</body></html>");
    return "".join(parts);
}


def _start_server(body_text: str) -> int {
    # Raw-socket HTTP server on 127.0.0.1:0 serving one canned body;
    # answers up to 8 requests then closes.
    srv = socket.socket();
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
    srv.bind(("127.0.0.1", 0));
    srv.listen(4);
    port = srv.getsockname()[1];
    body = body_text.encode("utf-8");
    head = (
        "HTTP/1.1 200 OK\r\n"
        + "Content-Type: text/html; charset=utf-8\r\n"
        + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n"
    ).encode("utf-8");

    def runner() -> None {
        srv.settimeout(15);
        served = 0;
        while served < 8 {
            try {
                accepted = srv.accept();
                conn = accepted[0];
            } except Exception {
                break;
            }
            try {
                conn.settimeout(5);
                conn.recv(65536);
                conn.sendall(head + body);
                conn.close();
            } except Exception {
            }
            served += 1;
        }
        try {
            srv.close();
        } except Exception {
        }
    }

    threading.Thread(target=runner, daemon=True).start();
    return port;
}


def _egress_available() -> bool {
    try {
        conn = socket.create_connection(("html.duckduckgo.com", 443), timeout=3);
        conn.close();
        return True;
    } except Exception {
        return False;
    }
}


test "validate_web_url rejects non-http schemes and garbage" {
    for bad in ["file:///etc/passwd", "ftp://example.com/x", "javascript:alert(1)", "", "   ", "not-a-url"] {
        res = validate_web_url(bad);
        assert str(res[0]) == "";
        assert len(str(res[1])) > 0;
    }
    good = validate_web_url("  https://example.com/page?q=1 ");
    assert str(good[1]) == "";
    assert str(good[0]) == "https://example.com/page?q=1";
}


test "truncate_result appends marker only past cap" {
    short = truncate_result("hello");
    assert short == "hello";
    big = "x" * (FETCH_BODY_CAP + 100);
    cut = truncate_result(big);
    assert len(cut) < len(big);
    assert cut.endswith("... [truncated]");
    assert cut.startswith("x" * 10);
}


test "strip_html removes scripts styles comments and tags" {
    page = _canned_page();
    text = strip_html(page);
    assert "Hello" in text;
    assert "World & friends" in text;
    assert "Canned Page" in text;
    assert "should-not-appear" not in text;
    assert "color: red" not in text;
    assert "<" not in text;
}


test "web_fetch renders local canned page over real http" {
    port = _start_server(_canned_page());
    old = os.environ.get("JACKAL_ALLOW_PRIVATE_HOSTS");
    os.environ["JACKAL_ALLOW_PRIVATE_HOSTS"] = "1";
    try {
        out = web_fetch(f"http://127.0.0.1:{port}/page");
        assert "# Canned Page" in out;
        assert "Hello" in out;
        assert "World & friends" in out;
        assert "<script>" not in out;
        assert "should-not-appear" not in out;
        assert '"ok"' not in out;
    } finally {
        if old is None {
            os.environ.pop("JACKAL_ALLOW_PRIVATE_HOSTS", None);
        } else {
            os.environ["JACKAL_ALLOW_PRIVATE_HOSTS"] = old;
        }
    }
}


test "validate_web_url blocks loopback private and metadata targets" {
    blocked = [
        "http://127.0.0.1/",
        "http://127.1.2.3:8080/x",
        "http://localhost/admin",
        "http://LOCALHOST./x",
        "http://foo.localhost/x",
        "https://10.0.0.5/",
        "http://172.16.4.4/",
        "http://192.168.1.1/",
        "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/",
        "http://[fd00::1]/",
        "http://metadata.google.internal/computeMetadata/v1/",
        "http://instance-data/latest/",
        "http://0.0.0.0/",
        "http://[::]/",
    ];
    for target in blocked {
        res = validate_web_url(target);
        assert str(res[0]) == "", target;
        assert len(str(res[1])) > 0, target;
        assert "lock" in str(res[1]) or "Invalid" in str(res[1]), (target, res[1]);
    }
    # A public literal is still allowed without any DNS lookup.
    ok = validate_web_url("https://93.184.216.34/page");
    assert str(ok[1]) == "", ok;
}


test "the private-host escape hatch only relaxes the guard when set" {
    old = os.environ.get("JACKAL_ALLOW_PRIVATE_HOSTS");
    try {
        os.environ["JACKAL_ALLOW_PRIVATE_HOSTS"] = "1";
        assert private_hosts_allowed();
        ok = validate_web_url("http://127.0.0.1:9/x");
        assert str(ok[1]) == "", ok;
        assert str(ok[0]) == "http://127.0.0.1:9/x", ok;
    } finally {
        if old is None {
            os.environ.pop("JACKAL_ALLOW_PRIVATE_HOSTS", None);
        } else {
            os.environ["JACKAL_ALLOW_PRIVATE_HOSTS"] = old;
        }
    }
    assert not private_hosts_allowed();
}


test "web_fetch refuses a blocked URL without touching the network" {
    out = web_fetch("http://169.254.169.254/latest/meta-data/");
    parsed = json.loads(out);
    assert parsed.get("ok") is False, out;
    assert "lock" in str(parsed.get("error", "")), out;
    assert web_fetch("http://127.0.0.1:1/") != "";
    parsed2 = json.loads(web_fetch("http://127.0.0.1:1/"));
    assert parsed2.get("ok") is False, parsed2;
}


test "resolved-address guard rejects loopback names and unresolvable hosts" {
    try {
        assert_host_resolves_public("localhost");
        assert False, "localhost must be rejected";
    } except ValueError as exc {
        assert "blocked" in str(exc).lower(), exc;
    }
    try {
        assert_host_resolves_public("no-such-host.invalid");
        assert False, "unresolvable host must be rejected";
    } except ValueError as exc {
        assert "resolve" in str(exc).lower(), exc;
    }
    # Public names only when egress/DNS is available (CI may be offline).
    if _egress_available() {
        assert_host_resolves_public("example.com");
    }
}


test "web_fetch fails loud with json error on bad scheme" {
    out = web_fetch("file:///etc/passwd");
    parsed = json.loads(out);
    assert parsed.get("ok") is False;
    assert "http(s)" in str(parsed.get("error", ""));
}


test "web_search fails loud on empty query without network" {
    out = web_search("");
    parsed = json.loads(out);
    assert parsed.get("ok") is False;
}


test "duckduckgo search returns formatted results when egress available" {
    net_off = os.environ.get("JACKAL_SKIP_NET_TESTS") == "1";
    if not net_off and _egress_available() {
        out = web_search("jac programming language");
        assert isinstance(out, str) and len(out) > 0;
        if out.startswith("1.") {
            assert "URL:" in out;
        }
        # Either formatted results or a graceful {"ok": false} JSON error -
        # never an exception across the seam.
        assert out.startswith("1.") or out == "No results found." or json.loads(out).get("ok") is False;
    }
}
