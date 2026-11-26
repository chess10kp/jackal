import secrets;
import base64;
import hashlib;
import time;
import http.server;
import urllib.parse;
import webbrowser;
import threading;
import queue;

glob LOGIN_EVENTS: any = queue.Queue(),
     _attempts: list[any] = [],
     _login_guard: any = threading.Lock();

obj LoginAttempt {
    has state: str = "",
        nonce: str = "",
        verifier: str = "",
        redirect_uri: str = "",
        host: str = "",
        client_id: str = "dynamic_agent_client",
        previous: dict[str, any] = {},
        callback: dict[str, str] = {},
        new_account: bool = False,
        cancelled: bool = False,
        server: any = None;
}

class LoginServer(http.server.HTTPServer) {
    has attempt: any = None;
}

class CallbackHandler(http.server.BaseHTTPRequestHandler) {
    override def log_message(format: str, *args: any);

    override def setup;

    def do_GET;
}

def finish_callback(attempt: LoginAttempt) -> dict[str, any];

def run_login(attempt: LoginAttempt);

def cancel_login;

def start_login(new_account: bool = False);

def poll_login -> dict[str, any];

def start_logout;
def run_logout(attempt: LoginAttempt);
