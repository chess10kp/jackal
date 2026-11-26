impl oauth_refresh_credentials(provider_id: str, credentials: dict[str, any]) -> dict[str, any] {
    return {
        "ok": False,
        "error": "network_not_supported",
        "provider": provider_id,
        "detail": ("OAuth token refresh needs HTTP against the provider token "
            "endpoint; the runtime loop must perform it and persist the "
            "resulting credential."),
    };
}

impl oauth_start_login(provider_id: str) -> dict[str, any] {
    return {
        "ok": False,
        "error": "network_not_supported",
        "provider": provider_id,
        "detail": ("Interactive OAuth login needs a browser + callback server; "
            "the runtime loop must drive it and persist the resulting "
            "credential."),
    };
}
