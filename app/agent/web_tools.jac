"""Web search + fetch tools - parity with src/agent/web-tools.ts.

Pure stdlib (urllib.request / urllib.parse + re + json), no new pip deps,
so this lowers in the server codespace like agent/tools.jac. Search backend:
the DuckDuckGo HTML endpoint (no API key, browser-y User-Agent). Both tools
fail loud {"ok": false}-style JSON strings instead of raising across the seam.

The Jac importer resolves web_tools.test.jac as the same-stem annex of this
module (plugin_hooks_events.jac pattern), so the offline test harness imports
(socket, threading) live here alongside the runtime imports.
"""

import re;
import json;
import html;
import os;
import socket;
import threading;
import ipaddress;
import urllib.parse;
import urllib.request;
import urllib.error;
import from .tool_spec { MAX_TOOL_RESULT }

glob WEB_TIMEOUT_SECS: int = 15,
     FETCH_BODY_CAP: int = MAX_TOOL_RESULT,
     DEFAULT_SEARCH_RESULTS: int = 5,
     MAX_FETCH_RESULTS: int = 20,
     MAX_REDIRECT_HOPS: int = 5,
     ALLOW_PRIVATE_ENV: str = "JACKAL_ALLOW_PRIVATE_HOSTS",
     REDIRECT_CODES: list[int] = [301, 302, 303, 307, 308],
     BLOCKED_HOSTS: list[str] = [
         "localhost",
         "localhost.localdomain",
         "ip6-localhost",
         "ip6-loopback",
         "metadata",
         "metadata.google.internal",
         "instance-data",
         "instance-data.ec2.internal",
     ],
     BLOCKED_SUFFIXES: list[str] = [
         ".localhost",
         ".local",
         ".internal",
         ".home.arpa",
     ],
     SEARCH_USER_AGENT: str = (
         "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
         "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
     );


"""True when the SSRF guard is explicitly relaxed (offline test servers).
Never set this in a normal session: it exists so the harness can bind a
loopback HTTP server and fetch from it."""
def private_hosts_allowed() -> bool {
    raw: str = str(os.environ.get(ALLOW_PRIVATE_ENV, "")).strip().lower();
    return raw in ("1", "on", "true", "yes");
}
sem private_hosts_allowed = "Escape hatch for loopback fetches in offline tests.";


"""True for addresses a model-controlled URL must never reach: loopback,
private, link-local, CGNAT, multicast, reserved, unspecified."""
def ip_is_public(addr: any) -> bool {
    try {
        return bool(
            addr.is_global
            and not addr.is_loopback
            and not addr.is_private
            and not addr.is_link_local
            and not addr.is_multicast
            and not addr.is_reserved
            and not addr.is_unspecified
        );
    } except Exception {
        return False;
    }
}
sem ip_is_public = "Classify an ipaddress object as a routable public address.";


"""Offline host check: literal blocked names/suffixes and IP literals.
Returns an error string, or "" when the host is acceptable. Hostname
resolution is deliberately NOT done here (validate stays offline/no-DNS);
`_assert_host_resolves_public` enforces the resolved-address check at
connect time."""
def host_block_reason(host: str) -> str {
    raw: str = str(host or "").strip();
    if not raw {
        return "missing host";
    }
    h: str = raw.lower().strip("[]").rstrip(".");
    if h in BLOCKED_HOSTS {
        return "blocked host '" + h + "'";
    }
    for suffix in BLOCKED_SUFFIXES {
        if h.endswith(suffix) {
            return "blocked host suffix '" + suffix + "'";
        }
    }
    try {
        addr = ipaddress.ip_address(h.split("%")[0]);
        if not ip_is_public(addr) {
            return "blocked address " + h;
        }
        return "";
    } except ValueError {
        return "";
    } except Exception {
        return "unparseable host '" + h + "'";
    }
    return "";
}
sem host_block_reason = "Reject loopback/private/metadata host literals without doing DNS.";


"""Resolve `host` and reject when ANY address is non-public. Raises
ValueError (caught by the tool seam) on a blocked or unresolvable host.
The check runs immediately before each connect so a redirect target is
re-screened too."""
def assert_host_resolves_public(host: str) -> None {
    if private_hosts_allowed() {
        return;
    }
    h: str = str(host or "").strip().lower().strip("[]");
    if not h {
        raise ValueError("url is missing a host");
    }
    reason: str = host_block_reason(h);
    if reason {
        raise ValueError(reason);
    }
    infos: any = None;
    try {
        infos = socket.getaddrinfo(h, None);
    } except Exception {
        raise ValueError("could not resolve host '" + h + "'");
    }
    for info in infos {
        addr_text: str = str(info[4][0]).split("%")[0];
        try {
            addr = ipaddress.ip_address(addr_text);
        } except Exception {
            raise ValueError("host '" + h + "' resolved to an unparseable address");
        }
        if not ip_is_public(addr) {
            raise ValueError(
                "host '" + h + "' resolves to blocked address " + addr_text
            );
        }
    }
}
sem assert_host_resolves_public = "Reject hosts whose resolved addresses are loopback/private/metadata.";


"""Validate an http(s) URL; reject everything else (no file://, no data:)
and refuse loopback/private/metadata hosts. Redirects are handled by the
caller (`_open_checked`), which re-validates every hop.
Returns ("", error_message) on failure."""
def validate_web_url(raw: str) -> tuple[str, str] {
    url = (raw or "").strip();
    if not url {
        return ("", "url is required");
    }
    parsed = urllib.parse.urlparse(url);
    if parsed.scheme not in ("http", "https") {
        scheme = parsed.scheme if parsed.scheme else "none";
        return ("", f"Only http(s) URLs are allowed (got scheme '{scheme}'): {url}");
    }
    if not parsed.netloc {
        return ("", f"Invalid URL (missing host): {url}");
    }
    if not private_hosts_allowed() {
        reason: str = host_block_reason(str(parsed.hostname or ""));
        if reason {
            return ("", f"Blocked URL ({reason}): {url}");
        }
    }
    return (url, "");
}
sem validate_web_url = "Reject non-http(s) and loopback/private/metadata URLs before any network I/O.";


"""Redirect handler that does not follow; `_open_checked` validates the
Location header before issuing the next request (urllib would otherwise
fetch a private/metadata target given a public redirector)."""
obj _NoRedirectHandler(urllib.request.HTTPRedirectHandler) {
    def redirect_request(req: any, fp: any, code: any, msg: any, headers: any, newurl: any) -> any {
        raise urllib.error.HTTPError(str(newurl), int(code), "redirect", headers, fp);
    }
}


"""Open `url`, following at most MAX_REDIRECT_HOPS redirects, and re-run the
scheme/host/DNS check on every hop. Raises ValueError for a blocked target;
callers at the tool seam turn that into a {"ok": false} payload."""
def _open_checked(url: str) -> any {
    vr: tuple[str, str] = validate_web_url(url);
    if str(vr[1]) {
        raise ValueError(str(vr[1]));
    }
    current: str = str(vr[0]);
    opener: any = urllib.request.build_opener(_NoRedirectHandler());
    hops: int = 0;
    while True {
        hop: any = urllib.parse.urlparse(current);
        assert_host_resolves_public(str(hop.hostname or ""));
        req: any = urllib.request.Request(
            current, headers={"User-Agent": SEARCH_USER_AGENT}
        );
        try {
            return opener.open(req, timeout=WEB_TIMEOUT_SECS);
        } except urllib.error.HTTPError as exc {
            code: int = int(exc.code);
            if not (code in REDIRECT_CODES) or hops >= MAX_REDIRECT_HOPS {
                raise exc;
            }
            location: str = "";
            try {
                if exc.headers {
                    location = str(exc.headers.get("Location", ""));
                }
            } except Exception {
                location = "";
            }
            if not location {
                raise exc;
            }
            next_url: str = urllib.parse.urljoin(current, location);
            hops += 1;
            try {
                exc.close();
            } except Exception {}
            vr2: tuple[str, str] = validate_web_url(next_url);
            if str(vr2[1]) {
                raise ValueError(str(vr2[1]));
            }
            current = str(vr2[0]);
        }
    }
    return None;
}
sem _open_checked = "HTTP open with SSRF-safe manual redirect following.";

"""Decode a DuckDuckGo outbound link into the real target URL."""
def _decode_ddg_href(href_attr: str) -> str {
    href: str = html.unescape(str(href_attr).strip());
    if href.startswith("//") {
        href = "https:" + href;
    }
    m = re.search(r"[?&]uddg=([^&]+)", href);
    if m is not None {
        href = urllib.parse.unquote(m.group(1));
    }
    return href;
}

"""Strip script/style blocks, comments, and tags down to readable text."""
def strip_html(page: str) -> str {
    t: str = str(page);
    t = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", t);
    t = re.sub(r"(?s)<!--.*?-->", " ", t);
    t = re.sub(r"(?s)<[^>]*>", " ", t);
    t = html.unescape(t);
    t = re.sub(r"[ \t\r\f\v]+", " ", t);
    t = re.sub(r"\s*\n\s*", "\n", t);
    t = re.sub(r"\n{3,}", "\n\n", t);
    return t.strip();
}
sem strip_html = "Regex-based HTML-to-text extraction (scripts/styles removed first).";

"""Cap tool output at the shared MAX_TOOL_RESULT convention."""
def truncate_result(text: str, cap: int = FETCH_BODY_CAP) -> str {
    body = str(text);
    if len(body) <= cap {
        return body;
    }
    return body[:cap] + "\n\n... [truncated]";
}

"""Extract the <title> of an HTML document, empty string when absent."""
def _extract_title(page: str) -> str {
    m = re.search(r"(?is)<title[^>]*>(.*?)</title>", str(page));
    if m is None {
        return "";
    }
    return strip_html(m.group(1));
}


"""web_search tool: top DDG hits as 'N. Title / URL: ... / snippet' lines.
Never raises; failures come back as {"ok": false, "error": ...} JSON."""
def web_search(query: str, num_results: int = DEFAULT_SEARCH_RESULTS) -> str {
    q = (query or "").strip();
    if not q {
        return json.dumps({"ok": False, "error": "query is required"});
    }
    n = max(1, min(int(num_results), MAX_FETCH_RESULTS));
    try {
        endpoint = "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": q});
        req = urllib.request.Request(endpoint, headers={"User-Agent": SEARCH_USER_AGENT});
        resp = urllib.request.urlopen(req, timeout=WEB_TIMEOUT_SECS);
        page = resp.read(FETCH_BODY_CAP * 4).decode("utf-8", errors="replace");
        resp.close();

        # Result anchors: <a class="result__a" href="...">Title</a>
        anchors = re.findall(
            r'(?is)<a\s([^>]*class="result__a"[^>]*)>(.*?)</a>', page
        );
        snippets = re.findall(
            r'(?is)<(?:a|td|div)[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</(?:a|td|div)>',
            page,
        );
        results: list[tuple[str, str, str]] = [];
        seen_urls: set[str] = set();
        for ent in enumerate(anchors) {
            idx = int(ent[0]);
            pair = ent[1];
            attrs = str(pair[0]);
            title = strip_html(pair[1]);
            href_m = re.search(r'href="([^"]+)"', attrs);
            if href_m is None or not title {
                continue;
            }
            url = _decode_ddg_href(href_m.group(1));
            if not url.startswith("http") or url in seen_urls {
                continue;
            }
            seen_urls.add(url);
            snippet = strip_html(snippets[idx]) if idx < len(snippets) else "";
            results.append((title, url, snippet));
            if len(results) >= n {
                break;
            }
        }
        if not results {
            return "No results found.";
        }
        blocks: list[str] = [];
        for hit_entry in enumerate(results) {
            i = int(hit_entry[0]);
            hit = hit_entry[1];
            lines = [f"{i + 1}. {hit[0]}", f"   URL: {hit[1]}"];
            if hit[2] {
                lines.append(f"   {hit[2]}");
            }
            blocks.append("\n".join(lines));
        }
        return truncate_result("\n\n".join(blocks));
    } except Exception as e {
        return json.dumps({"ok": False, "error": f"Search failed for '{q}': {e}"});
    }
}
sem web_search = "Search the web (DuckDuckGo HTML backend) and return the top results with titles, URLs, and snippets. Use for docs, releases, and facts not in the repo.";
sem web_search.query = "Search query.";
sem web_search.num_results = "Max results to return (default 5, capped at 20).";


"""web_fetch tool: fetch an http(s) page and return readable stripped text.
Body is capped after decode; never raises across the seam."""
def web_fetch(url: str) -> str {
    vr = validate_web_url(url);
    target = str(vr[0]);
    err = str(vr[1]);
    if err {
        return json.dumps({"ok": False, "error": err});
    }
    try {
        resp = _open_checked(target);
        raw = resp.read(FETCH_BODY_CAP * 4);
        ctype = str(resp.headers.get("Content-Type", ""));
        resp.close();
        text = raw.decode("utf-8", errors="replace");
        looks_html = "html" in ctype.lower() or bool(
            re.search(r"(?i)<html|<body|<div|<!doctype", text[:2000])
        );
        header = "";
        if looks_html {
            title = _extract_title(text);
            if title {
                header = f"# {title}\n\n";
            }
            text = strip_html(text);
        }
        if not text.strip() {
            return json.dumps({"ok": False, "error": f"Fetched {target} but it has no readable text."});
        }
        return truncate_result(header + text.strip());
    } except Exception as e {
        return json.dumps({"ok": False, "error": f"Fetch failed for {target}: {e}"});
    }
}
sem web_fetch = "Fetch an http(s) URL and return readable text (HTML stripped, ~50KB cap). Use after web_search when you need page content.";
sem web_fetch.url = "http(s) URL to fetch.";


"""Native-safe dictionary-ABI adapters for web tools."""
def _web_search_tool(args: dict[str, any]) -> str {
    raw_n: any = args.get("num_results", DEFAULT_SEARCH_RESULTS);
    n = int(raw_n) if raw_n is not None else DEFAULT_SEARCH_RESULTS;
    return web_search(str(args.get("query", "")), n);
}

def _web_fetch_tool(args: dict[str, any]) -> str {
    return web_fetch(str(args.get("url", "")));
}

"""Legacy schema export retained for callers outside agent.tools.
The production registry uses typed `make_tool_spec` calls in tools.jac so it
does not unpack untyped dictionaries into a constructor."""
def tool_specs_web() -> list[dict[str, any]] {
    return [
        {
            "name": "web_search",
            "description": "Search the web (DuckDuckGo HTML backend) and return the top results with titles, URLs, and snippets. Use for docs, releases, and facts not in the repo.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query."},
                    "num_results": {"type": "integer", "description": "Max results (default 5, capped at 20)."},
                },
                "required": ["query"],
            },
            "handler": _web_search_tool,
        },
        {
            "name": "web_fetch",
            "description": "Fetch an http(s) URL and return readable text (HTML stripped, ~50KB cap). Use after web_search when you need page content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "http(s) URL to fetch."},
                },
                "required": ["url"],
            },
            "handler": _web_fetch_tool,
        },
    ];
}
