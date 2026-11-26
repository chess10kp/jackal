import json;
import os;
import from .openai_identity { validate_identity }

def _fixtures -> dict[str, any] {
    path = os.path.join(os.path.dirname(__file__), "openai_identity.fixtures.json");
    with open(path) as source {
        return json.load(source);
    }
}

test "native OpenSSL accepts a signed identity and rejects signature tampering" {
    fixture = _fixtures();
    token = str(fixture["valid"]);
    keys: dict[str, any] = fixture["jwks"];
    claims = validate_identity(token, keys, "oaiapp_test", "test-nonce", at=1500);
    assert claims["sub"] == "test-subject", "verified subject";
    parts = token.split(".");
    parts[2] = ("A" if parts[2][0] != "A" else "B") + parts[2][1:];
    rejected = False;
    try {
        validate_identity(".".join(parts), keys, "oaiapp_test", "test-nonce", at=1500);
    } except ValueError {
        rejected = True;
    }
    assert rejected, "tampered signature must fail";
}

test "signed invalid claims and unsupported algorithms fail closed" {
    fixture = _fixtures();
    keys: dict[str, any] = fixture["jwks"];
    for name in ["wrong_issuer", "wrong_audience", "wrong_nonce", "expired", "future", "none"] {
        rejected = False;
        try {
            validate_identity(str(fixture[name]), keys, "oaiapp_test", "test-nonce", at=1500);
        } except ValueError {
            rejected = True;
        }
        assert rejected, name + " must fail";
    }
}

test "account substitution unknown keys and malformed tokens fail closed" {
    fixture = _fixtures();
    keys: dict[str, any] = fixture["jwks"];
    for token in ["", "a.b", "a.b.c", str(fixture["valid"])] {
        rejected = False;
        try {
            validate_identity(token, keys, "oaiapp_test", "test-nonce", subject="another-subject", at=1500);
        } except ValueError {
            rejected = True;
        }
        assert rejected, "malformed token or account substitution must fail";
    }
    rejected = False;
    try {
        validate_identity(str(fixture["valid"]), {"keys": []}, "oaiapp_test", "test-nonce", at=1500);
    } except ValueError {
        rejected = True;
    }
    assert rejected, "unknown signing key must fail";
}
