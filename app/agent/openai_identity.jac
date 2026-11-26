"""OpenAI OIDC validation. RSA operations belong to OpenSSL, never Jac math.

Only RS256 signing keys from the issuer's fixed JWKS endpoint are accepted.
No token-controlled URL or algorithm is used to select verification code.
"""
import base64;
import json;
import time;
import re;

import from crypto {
    def BIO_new_mem_buf(buf: bytes, length: i32) -> ptr;
    def BIO_free(bio: ptr) -> i32;
    def PEM_read_bio_PUBKEY(bio: ptr, key: ptr, cb: ptr, user: ptr) -> ptr;
    def EVP_PKEY_free(key: ptr);
    def EVP_MD_CTX_new -> ptr;
    def EVP_MD_CTX_free(ctx: ptr);
    def EVP_sha256 -> ptr;
    def EVP_DigestVerifyInit(ctx: ptr, pctx: ptr, md: ptr, engine: ptr, key: ptr) -> i32;
    def EVP_DigestVerify(ctx: ptr, sig: bytes, siglen: u64, data: bytes, length: u64) -> i32;
}

def decode_url(value: str) -> bytes {
    if not value or not re.fullmatch(r"[A-Za-z0-9_-]+", value) {
        raise ValueError("invalid base64url");
    }
    return base64.urlsafe_b64decode(value + "=" * ((4 - len(value) % 4) % 4));
}

def _der(tag: int, value: bytes) -> bytes {
    size = len(value);
    length = bytes([size]) if size < 128 else b"\x82" + bytes([size >> 8, size & 255]);
    return bytes([tag]) + length + value;
}

def _integer(value: bytes) -> bytes {
    raw = value.lstrip(b"\x00");
    if not raw {
        raise ValueError("empty RSA integer");
    }
    if raw[0] & 128 {
        raw = b"\x00" + raw;
    }
    return _der(2, raw);
}

def _public_pem(key: dict[str, any]) -> bytes {
    modulus = decode_url(str(key.get("n", "")));
    exponent = decode_url(str(key.get("e", "")));
    if len(modulus) < 256 or len(modulus) > 1024 or len(exponent) > 8 {
        raise ValueError("unsupported RSA key size");
    }
    rsa = _der(48, _integer(modulus) + _integer(exponent));
    algorithm = b"\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00";
    der = _der(48, algorithm + _der(3, b"\x00" + rsa));
    return b"-----BEGIN PUBLIC KEY-----\n" + base64.b64encode(der) + b"\n-----END PUBLIC KEY-----\n";
}

def _verify_rs256(key: dict[str, any], signature: bytes, message: bytes) -> bool {
    pem = _public_pem(key);
    bio = BIO_new_mem_buf(pem, i32(len(pem)));
    if bio.is_null() {
        raise ValueError("could not allocate public key buffer");
    }
    public_key = PEM_read_bio_PUBKEY(bio, ptr(), ptr(), ptr());
    BIO_free(bio);
    if public_key.is_null() {
        raise ValueError("invalid RSA public key");
    }
    ctx = EVP_MD_CTX_new();
    try {
        if ctx.is_null() {
            raise ValueError("could not allocate signature verifier");
        }
        if EVP_DigestVerifyInit(ctx, ptr(), EVP_sha256(), ptr(), public_key) != 1 {
            raise ValueError("could not initialize signature verifier");
        }
        return EVP_DigestVerify(ctx, signature, u64(len(signature)), message, u64(len(message))) == 1;
    } finally {
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(public_key);
    }
}

def validate_identity(token: str, jwks: dict[str, any], client_id: str,
                      nonce: str, subject: str = "", at: int = -1) -> dict[str, any] {
    if len(token) > 65536 or not client_id or client_id == "dynamic_agent_client" {
        raise ValueError("invalid ID token or client ID");
    }
    parts = token.split(".");
    if len(parts) != 3 {
        raise ValueError("invalid ID token");
    }
    header: any = json.loads(decode_url(parts[0]));
    claims: any = json.loads(decode_url(parts[1]));
    if not isinstance(header, dict) or not isinstance(claims, dict) {
        raise ValueError("invalid ID token objects");
    }
    if header.get("alg") != "RS256" or header.get("crit") or not header.get("kid") {
        raise ValueError("unsupported ID token header");
    }
    keys: any = jwks.get("keys", []);
    matches: list[dict[str, any]] = [];
    for key in keys {
        if isinstance(key, dict) and key.get("kid") == header["kid"] {
            if key.get("kty") == "RSA" and key.get("use", "sig") == "sig" and key.get("alg", "RS256") == "RS256" {
                matches.append(key);
            }
        }
    }
    if len(matches) != 1 or not _verify_rs256(matches[0], decode_url(parts[2]), (parts[0] + "." + parts[1]).encode("ascii")) {
        raise ValueError("ID token signature rejected");
    }
    now = at if at >= 0 else int(time.time());
    audience: any = claims.get("aud");
    if audience != client_id and not (isinstance(audience, list) and client_id in audience) {
        raise ValueError("ID token audience rejected");
    }
    if isinstance(audience, list) and len(audience) > 1 and claims.get("azp") != client_id {
        raise ValueError("ID token authorized party rejected");
    }
    if claims.get("iss") != "https://auth.openai.com" {
        raise ValueError("ID token issuer rejected");
    }
    for name in ["exp", "iat"] {
        value: any = claims.get(name);
        if isinstance(value, bool) or not isinstance(value, (int, float)) {
            raise ValueError("ID token timestamp missing");
        }
    }
    if claims["exp"] <= now or claims["iat"] > now + 5 or claims.get("nbf", 0) > now + 5 {
        raise ValueError("ID token is outside its validity period");
    }
    if nonce and claims.get("nonce") != nonce {
        raise ValueError("ID token nonce rejected");
    }
    if not isinstance(claims.get("sub"), str) or not claims["sub"] or (subject and claims["sub"] != subject) {
        raise ValueError("ID token subject rejected");
    }
    return claims;
}
