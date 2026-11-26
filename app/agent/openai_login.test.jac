import os;
import json;
import stat;
import tempfile;
import threading;
import urllib.request;
import urllib.error;
import from .openai_login { LoginAttempt, LoginServer, CallbackHandler, finish_callback }
import from .openai_accounts {
    host_identity,
    read_accounts,
    write_accounts,
    save_account,
    selected_account,
    account_path,
    token_record,
    access_token,
}

test "callback state and issued registration are checked before token exchange" {
    for callback in [
        {"state": "wrong", "code": "secret", "client_id": "oaiapp_test"},
        {
            "state": "pending",
            "error": "access_denied",
            "code": "secret",
            "client_id": "oaiapp_test",
        },
        {"state": "pending", "code": "secret", "client_id": "dynamic_agent_client"},
        {"state": "pending", "code": "secret", "client_id": ""},
    ] {
        attempt = LoginAttempt(state="pending", callback=callback);
        rejected = False;
        try {
            finish_callback(attempt);
        } except ValueError {
            rejected = True;
        }
        assert rejected, "invalid callback must not exchange credentials";
    }
    attempt = LoginAttempt(
        state="pending",
        client_id="oaiapp_original",
        callback={"state": "pending", "code": "secret", "client_id": "oaiapp_other"},
    );
    rejected = False;
    try {
        finish_callback(attempt);
    } except ValueError {
        rejected = True;
    }
    assert rejected, "returning account cannot replace its registered client";
}

test "account store retains registrations and creates private atomic files" {
    old = os.environ.get("JACKAL_AGENT_DIR");
    with tempfile.TemporaryDirectory() as directory {
        os.environ["JACKAL_AGENT_DIR"] = directory;
        try {
            host = host_identity();
            assert host.startswith("urn:uuid:"), "host identity uses a random UUID";
            assert host_identity() == host, "host identity survives restart";
            first: dict[str, any] = {
                "client_id": "first",
                "subject": "subject",
                "refresh": "first-refresh",
                "access": "first-access",
                "expires": 4102444800000,
            };
            second: dict[str, any] = {
                "client_id": "second",
                "subject": "subject",
                "refresh": "second-refresh",
                "access": "second-access",
                "expires": 4102444800000,
            };
            save_account(first);
            save_account(second);
            data = read_accounts();
            assert access_token("first:subject")
                == "first-access", "an existing turn retains its captured account";
            assert access_token() == "second-access", "new turns use the selected account";
            assert len(data["accounts"]) == 2, "same subject registrations remain separate";
            assert selected_account()["refresh"] == "second-refresh", "new account becomes active";
            assert stat.S_IMODE(os.stat(account_path()).st_mode)
                == 384, "credentials are owner-only";
            data["accounts"]["second:subject"]["refresh"] = "rotated";
            write_accounts(data);
            assert selected_account()["refresh"] == "rotated", "replacement is durable";
            assert not [
                name
                for name in os.listdir(directory)
                if name.startswith(".openai-")
            ], "no temporary credential files remain";
        } finally {
            if old is None {
                os.environ.pop("JACKAL_AGENT_DIR", None);
            } else {
                os.environ["JACKAL_AGENT_DIR"] = old;
            }
        }
    }
}

test "identity alone does not grant ChatGPT plan use" {
    tokens: dict[str, any] = {
        "access_token": "access",
        "refresh_token": "refresh",
        "token_type": "Bearer",
        "expires_in": 3600,
        "scope": "openid email profile",
    };
    rejected = False;
    try {
        token_record(tokens, "oaiapp_test", "nonce", "host", {});
    } except ValueError {
        rejected = True;
    }
    assert rejected, "plan scope is required before identity or inference";
}

test "loopback listener rejects foreign state duplicate fields and wrong paths" {
    attempt = LoginAttempt(state="pending");
    server = LoginServer(("127.0.0.1", 0), CallbackHandler);
    server.attempt = attempt;
    thread = threading.Thread(target=server.serve_forever, args=(0.01,), daemon=True);
    thread.start();
    base = "http://127.0.0.1:" + str(server.server_address[1]);
    try {
        for path in [
            "/auth/callback?state=foreign&code=secret",
            "/wrong?state=pending&code=secret",
            "/auth/callback?state=pending&state=&code=secret",
        ] {
            rejected = False;
            try {
                with urllib.request.urlopen(base + path, timeout=3.0) as response {
                    response.read();
                }
            } except urllib.error.HTTPError as error {
                rejected = error.code == 400;
            }
            assert rejected
                and not attempt.callback, "invalid request cannot consume the pending login";
        }
        with urllib.request.urlopen(
            base + "/auth/callback?state=pending&error=access_denied", timeout=3.0
        ) as response {
            assert response.status == 200, "state-validated denial is delivered to the worker";
        }
        assert attempt.callback["error"] == "access_denied", "denial remains distinct from a code";
    } finally {
        server.shutdown();
        server.server_close();
        thread.join(timeout=3.0);
    }
}

test "refresh rotates credentials together and preserves omitted granted scopes" {
    previous: dict[str, any] = {
        "subject": "subject",
        "email": "test@example.invalid",
        "id_token": "old-id",
        "refresh": "old-refresh",
        "scopes": ["chatgpt.tokens.use.direct", "openid"],
    };
    tokens: dict[str, any] = {
        "access_token": "new-access",
        "refresh_token": "new-refresh",
        "token_type": "Bearer",
        "expires_in": 3600,
    };
    record = token_record(tokens, "oaiapp_test", "", "host", previous);
    assert record["access"] == "new-access"
        and record["refresh"] == "new-refresh", "rotated pair is one record";
    assert record["subject"] == "subject"
        and record["id_token"]
            == "old-id", "refresh cannot change account identity without an ID token";
    assert "chatgpt.tokens.use.direct"
        in record["scopes"], "omitted scope preserves original grant";
    tokens["scope"] = "";
    rejected = False;
    try {
        token_record(tokens, "oaiapp_test", "", "host", previous);
    } except ValueError {
        rejected = True;
    }
    assert rejected, "explicitly removed plan permission cannot inherit the old scope";
}
