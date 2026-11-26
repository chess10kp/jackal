impl CallbackHandler.log_message(format: str, *args: any) {}

impl CallbackHandler.setup {
    self.request.settimeout(2.0);
    http.server.BaseHTTPRequestHandler.setup(self);
}

impl CallbackHandler.do_GET {
    attempt: LoginAttempt = (self.server as LoginServer).attempt;
    parsed = urllib.parse.urlparse(self.path);
    values: dict[str, list[str]] = urllib.parse.parse_qs(
        parsed.query, keep_blank_values=True, max_num_fields=16
    );
    valid: bool = parsed.path == "/auth/callback";
    result: dict[str, str] = {};
    for key in ["state", "code", "error", "client_id"] {
        items: any = values.get(key, []);
        if len(items) > 1 {
            valid = False;
        }
        result[key] = str(items[0]) if len(items) == 1 else "";
    }
    if not secrets.compare_digest(result["state"], attempt.state) {
        valid = False;
    }
    if not valid {
        self.send_response(400);
        self.end_headers();
        self.wfile.write(b"Invalid sign-in callback. Return to Jackal.");
        return;
    }
    if not attempt.callback {
        attempt.callback = result;
    }
    self.send_response(200);
    self.send_header("Content-Type", "text/plain; charset=utf-8");
    self.send_header("Cache-Control", "no-store");
    self.send_header("Referrer-Policy", "no-referrer");
    self.end_headers();
    self.wfile.write(b"Sign-in response received. Return to Jackal to check the result.");
}

impl finish_callback(attempt: LoginAttempt) -> dict[str, any] {
    result = attempt.callback;
    if not secrets.compare_digest(str(result.get("state", "")), attempt.state) {
        raise ValueError("Sign-in state did not match");
    }
    if result.get("error") {
        raise ValueError("ChatGPT authorization was declined or failed");
    }
    issued = str(result.get("client_id", ""));
    if attempt.client_id != "dynamic_agent_client" {
        if issued and issued != attempt.client_id {
            raise ValueError("ChatGPT registration changed");
        }
        issued = attempt.client_id;
    }
    if not issued or issued == "dynamic_agent_client" or not result.get("code") {
        raise ValueError("ChatGPT registration was incomplete; start sign-in again");
    }
    tokens = request_json(
        ISSUER + "/api/accounts/oauth/token",
        {
            "grant_type": "authorization_code",
            "client_id": issued,
            "code": str(result["code"]),
            "code_verifier": attempt.verifier,
            "redirect_uri": attempt.redirect_uri,
            "resource": RESOURCE,
        },
    );
    return token_record(tokens, issued, attempt.nonce, attempt.host, attempt.previous);
}

impl run_login(attempt: LoginAttempt) {
    try {
        attempt.previous = {} if attempt.new_account else selected_account();
        attempt.client_id = str(attempt.previous.get("client_id", "dynamic_agent_client"));
        attempt.host = host_identity();
        attempt.state = secrets.token_urlsafe(32);
        attempt.nonce = secrets.token_urlsafe(32);
        attempt.verifier = secrets.token_urlsafe(64);
        server = LoginServer(("127.0.0.1", 0), CallbackHandler);
        server.timeout = 0.25;
        server.attempt = attempt;
        attempt.server = server;
        attempt.redirect_uri = "http://127.0.0.1:"
            + str(server.server_address[1])
            + "/auth/callback";
        fields: dict[str, str] = {
            "client_id": attempt.client_id,
            "ext_agent_host_id": attempt.host,
            "response_type": "code",
            "redirect_uri": attempt.redirect_uri,
            "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
            "resource": RESOURCE,
            "state": attempt.state,
            "nonce": attempt.nonce,
            "code_challenge_method": "S256",
            "code_challenge": base64.urlsafe_b64encode(
                hashlib.sha256(attempt.verifier.encode("ascii")).digest()
            ).decode("ascii").rstrip("="),
        };
        if attempt.client_id == "dynamic_agent_client" {
            fields["agent_name_hint"] = "Jackal";
        } elif attempt.previous.get("email") {
            fields["login_hint"] = str(attempt.previous["email"]);
        }
        url = ISSUER + "/api/accounts/authorize?" + urllib.parse.urlencode(fields);
        LOGIN_EVENTS.put({"kind": "browser", "attempt": attempt, "url": url});
        webbrowser.open(url);
        deadline = time.monotonic() + 300.0;
        while not attempt.cancelled and not attempt.callback and time.monotonic() < deadline {
            server.handle_request();
        }
        if attempt.cancelled {
            return;
        }
        if not attempt.callback {
            raise ValueError("ChatGPT sign-in timed out; try /login openai again");
        }
        record = finish_callback(attempt);
        with _login_guard {
            if attempt.cancelled {
                return;
            }
            save_account(record);
        }
        LOGIN_EVENTS.put({"kind": "success", "attempt": attempt});
    } except Exception {
        if not attempt.cancelled {
            LOGIN_EVENTS.put({
                "kind": "error",
                "attempt": attempt,
                "message": "ChatGPT sign-in failed. Check authorization and network access, then try /login openai again.",
            });
        }
    } finally {
        if attempt.server is not None {
            attempt.server.server_close();
        }
    }
}

impl cancel_login {
    with _login_guard {
        for attempt in _attempts {
            attempt.cancelled = True;
        }
        _attempts.clear();
    }
}

impl start_login(new_account: bool = False) {
    cancel_login();
    attempt = LoginAttempt(new_account=new_account);
    _attempts.append(attempt);
    worker = threading.Thread(target=run_login, args=(attempt,), daemon=True);
    worker.start();
}

impl poll_login -> dict[str, any] {
    while True {
        try {
            event: any = LOGIN_EVENTS.get_nowait();
        } except queue.Empty {
            return {};
        }
        if not event["attempt"].cancelled {
            return event;
        }
    }
}

impl run_logout(attempt: LoginAttempt) {
    try {
        message = logout_account();
        LOGIN_EVENTS.put({"kind": "logout", "attempt": attempt, "message": message});
    } except Exception {
        LOGIN_EVENTS.put({
            "kind": "error",
            "attempt": attempt,
            "message": "Could not sign out of ChatGPT; check the account store is writable",
        });
    }
}

impl start_logout {
    cancel_login();
    attempt = LoginAttempt();
    _attempts.append(attempt);
    worker = threading.Thread(target=run_logout, args=(attempt,), daemon=True);
    worker.start();
}
