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
import from urllib.request { Request }

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
     BLOCKED_SUFFIXES: list[str] = [".localhost", ".local", ".internal", ".home.arpa"],
     SEARCH_USER_AGENT: str = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
         "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36");
def private_hosts_allowed -> bool;

sem private_hosts_allowed = "Escape hatch for loopback fetches in offline tests.";
def ip_is_public(addr: any) -> bool;

sem ip_is_public = "Classify an ipaddress object as a routable public address.";
def host_block_reason(host: str) -> str;

sem host_block_reason = "Reject loopback/private/metadata host literals without doing DNS.";
def assert_host_resolves_public(host: str);

sem assert_host_resolves_public = "Reject hosts whose resolved addresses are loopback/private/metadata.";
def validate_web_url(raw: str) -> tuple[str, str];

sem validate_web_url = "Reject non-http(s) and loopback/private/metadata URLs before any network I/O.";

obj _NoRedirectHandler(urllib.request.HTTPRedirectHandler) {
    def redirect_request(
        req: Request, fp: any, code: int, msg: str, headers: any, newurl: str
    ) -> Request | None;
}

def _open_checked(url: str) -> any;

sem _open_checked = "HTTP open with SSRF-safe manual redirect following.";
def _decode_ddg_href(href_attr: str) -> str;
def strip_html(page: str) -> str;

sem strip_html = "Regex-based HTML-to-text extraction (scripts/styles removed first).";
def truncate_result(text: str, cap: int = FETCH_BODY_CAP) -> str;
def _extract_title(page: str) -> str;
def web_search(query: str, num_results: int = DEFAULT_SEARCH_RESULTS) -> str;

sem web_search = "Search the web (DuckDuckGo HTML backend) and return the top results with titles, URLs, and snippets. Use for docs, releases, and facts not in the repo.";
sem web_search.query = "Search query.";
sem web_search.num_results = "Max results to return (default 5, capped at 20).";
def web_fetch(url: str) -> str;

sem web_fetch = "Fetch an http(s) URL and return readable text (HTML stripped, ~50KB cap). Use after web_search when you need page content.";
sem web_fetch.url = "http(s) URL to fetch.";
def _web_search_tool(args: dict[str, any]) -> str;

def _web_fetch_tool(args: dict[str, any]) -> str;
def tool_specs_web -> list[dict[str, any]];
