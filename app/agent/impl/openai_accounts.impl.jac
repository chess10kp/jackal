impl account_path -> str {
    return os.path.join(
        os.environ.get("JACKAL_AGENT_DIR", os.path.expanduser("~/.jackal")), "openai-accounts.json"
    );
}

impl read_accounts -> dict[str, any] {
    path = account_path();
    if not os.path.exists(path) {
        return {"accounts": {}, "active": ""};
    }
    with open(path) as source {
        data: any = json.load(source);
    }
    if not isinstance(data, dict) or not isinstance(data.get("accounts"), dict) {
        raise ValueError("Invalid OpenAI account store");
    }
    return data;
}

impl write_accounts(data: dict[str, any]) {
    path = account_path();
    directory = os.path.dirname(path);
    os.makedirs(directory, mode=448, exist_ok=True);
    (fd, temporary) = tempfile.mkstemp(prefix=".openai-", dir=directory);
    try {
        with os.fdopen(fd, "w") as target {
            target.write(json.dumps(data));
            target.flush();
            os.fsync(target.fileno());
        }
        os.replace(temporary, path);
    } finally {
        if os.path.exists(temporary) {
            os.unlink(temporary);
        }
    }
}

impl account_lock -> any {
    directory = os.path.dirname(account_path());
    os.makedirs(directory, mode=448, exist_ok=True);
    fd = os.open(account_path() + ".lock", os.O_CREAT | os.O_RDWR, 384);
    lock = os.fdopen(fd, "a+");
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX);
    return lock;
}

impl request_json(
    url: str, fields: dict[str, str] | None = None, bearer: str = ""
) -> dict[str, any] {
    headers: dict[str, str] = {"Accept": "application/json"};
    if bearer {
        headers["Authorization"] = "Bearer " + bearer;
    }
    body: bytes | None = None;
    if fields is not None {
        headers["Content-Type"] = "application/x-www-form-urlencoded";
        body = urllib.parse.urlencode(fields).encode("ascii");
    }
    req = urllib.request.Request(url, data=body, headers=headers);
    with urllib.request.urlopen(req, timeout=20.0) as response {
        data: any = json.loads(response.read(1048576).decode("utf-8"));
        if not isinstance(data, dict) {
            raise ValueError("Invalid OpenAI response");
        }
        return data;
    }
}

impl selected_account -> dict[str, any] {
    data = read_accounts();
    record: any = data["accounts"].get(str(data.get("active", "")), {});
    return record if isinstance(record, dict) else {};
}

impl configured_account -> bool {
    try {
        return bool(selected_account().get("refresh", ""));
    } except Exception {
        return False;
    }
}

impl host_identity -> str {
    with account_lock() {
        data = read_accounts();
        host = str(data.get("host_id", ""));
        if not host {
            host = "urn:uuid:" + str(uuid.uuid4());
            data["host_id"] = host;
            write_accounts(data);
        }
        return host;
    }
}

impl token_record(
    tokens: dict[str, any], client_id: str, nonce: str, host: str, previous: dict[str, any]
) -> dict[str, any] {
    access: any = tokens.get("access_token");
    refresh: any = tokens.get("refresh_token", previous.get("refresh", ""));
    identity: any = tokens.get("id_token");
    expires: any = tokens.get("expires_in");
    if not isinstance(access, str) or not access or not isinstance(refresh, str) or not refresh {
        raise ValueError("OpenAI did not return renewable credentials");
    }
    if str(tokens.get("token_type", "")).lower() != "bearer" {
        raise ValueError("OpenAI returned an unsupported token type");
    }
    if isinstance(expires, bool)
        or not isinstance(expires, (int, float))
        or expires <= 0
        or expires > 31536000
    {
        raise ValueError("OpenAI returned an invalid token lifetime");
    }
    scope: any = tokens.get("scope");
    scopes: list[str] = str(scope).split() if isinstance(scope, str) else [];
    if scope is None and previous {
        scopes = previous.get("scopes", []);
    }
    if "chatgpt.tokens.use.direct" not in scopes {
        raise ValueError("ChatGPT plan usage was not granted; authorize it before using models");
    }
    claims: dict[str, any] = {};
    if isinstance(identity, str) and identity {
        keys = request_json(ISSUER + "/.well-known/jwks.json");
        claims = validate_identity(
            identity, keys, client_id, nonce, str(previous.get("subject", ""))
        );
    } elif nonce or not previous {
        raise ValueError("OpenAI did not return an ID token");
    } else {
        claims = {"sub": previous.get("subject", ""), "email": previous.get("email", "")};
        identity = previous.get("id_token", "");
    }
    return {
        "type": "oauth",
        "client_id": client_id,
        "host_id": host,
        "subject": claims["sub"],
        "email": claims.get("email", ""),
        "id_token": identity,
        "access": access,
        "refresh": refresh,
        "expires": int((time.time() + float(expires)) * 1000),
        "scopes": scopes,
    };
}

impl save_account(record: dict[str, any]) {
    with account_lock() {
        data = read_accounts();
        key = str(record["client_id"]) + ":" + str(record["subject"]);
        data["accounts"][key] = record;
        data["active"] = key;
        write_accounts(data);
    }
}

impl access_token(account_key: str = "") -> str {
    with account_lock() {
        data = read_accounts();
        key = account_key or str(data.get("active", ""));
        record: dict[str, any] = data["accounts"].get(key, {});
        if not record.get("refresh") {
            raise ValueError("Use /login openai to continue with ChatGPT");
        }
        if int(record.get("expires", 0)) > int(time.time() * 1000) + 60000 {
            return str(record["access"]);
        }
        tokens = request_json(
            ISSUER + "/api/accounts/oauth/token",
            {
                "grant_type": "refresh_token",
                "refresh_token": str(record["refresh"]),
                "client_id": str(record["client_id"]),
                "resource": RESOURCE,
            },
        );
        updated = token_record(
            tokens, str(record["client_id"]), "", str(record["host_id"]), record
        );
        data["accounts"][key] = updated;
        write_accounts(data);
        return str(updated["access"]);
    }
}

impl logout_account -> str {
    with account_lock() {
        data = read_accounts();
        key = str(data.get("active", ""));
        record: dict[str, any] = data["accounts"].get(key, {});
        refresh = str(record.get("refresh", ""));
        for field in ["access", "refresh", "id_token", "expires", "scopes"] {
            record.pop(field, None);
        }
        if key {
            data["accounts"][key] = record;
        }
        write_accounts(data);
        if not refresh {
            return "No active ChatGPT session";
        }
        try {
            discovery = request_json(ISSUER + "/.well-known/openid-configuration");
            endpoint = str(discovery.get("revocation_endpoint", ""));
            if not endpoint.startswith(ISSUER + "/") {
                raise ValueError("Invalid revocation endpoint");
            }
            fields: dict[str, str] = {
                "token": refresh,
                "token_type_hint": "refresh_token",
                "client_id": str(record["client_id"]),
            };
            req = urllib.request.Request(
                endpoint,
                data=urllib.parse.urlencode(fields).encode("ascii"),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            );
            with urllib.request.urlopen(req, timeout=20.0) as response {
                response.read(4096);
            }
            return "Signed out of ChatGPT";
        } except Exception {
            return "Signed out locally; remote session revocation could not be confirmed";
        }
    }
}

impl select_account(key: str) -> bool {
    with account_lock() {
        data = read_accounts();
        record: any = data["accounts"].get(key);
        if not isinstance(record, dict) {
            raise ValueError("Unknown ChatGPT account");
        }
        data["active"] = key;
        write_accounts(data);
        return bool(record.get("refresh", ""));
    }
}

impl account_revision -> str {
    try {
        record = selected_account();
        return str(record.get("client_id", "")) + ":" + str(record.get("subject", ""))
            if record.get("refresh")
            else "";
    } except Exception {
        return "";
    }
}
