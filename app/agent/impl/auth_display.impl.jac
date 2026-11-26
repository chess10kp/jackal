impl redact_secret(secret: any, visible: int = 4) -> str {
    if not isinstance(secret, str) or not secret {
        return "(unset)";
    }
    if len(secret) <= visible + 4 {
        return "*" * 8;
    }
    return "*" * 8 + secret[-visible:];
}

impl redact_credential(cred: any) -> dict[str, any] | None {
    if not isinstance(cred, dict) {
        return None;
    }
    out: dict[str, any] = {};
    for (k, v) in cred.items() {
        if k == "type" {
            out[k] = v;
        } elif isinstance(v, str) {
            out[k] = redact_secret(v);
        } else {
            out[k] = v;
        }
    }
    return out;
}

impl validate_provider_entry(item: any) -> dict[str, any] | None {
    if not isinstance(item, dict) {
        return None;
    }
    pid = item.get("id");
    display = item.get("displayName");
    auth_type = item.get("authType");
    if not isinstance(pid, str) or not pid {
        return None;
    }
    if not isinstance(display, str) or not display {
        return None;
    }
    if auth_type not in KNOWN_AUTH_TYPES {
        return None;
    }
    return {
        "id": pid,
        "displayName": display,
        "authType": auth_type,
        "configured": bool(item.get("configured", False)),
        "modelCount": int(item.get("modelCount", 0)),
    };
}

impl login_kind(auth_type: any) -> str {
    if auth_type in KNOWN_AUTH_TYPES {
        return str(auth_type);
    }
    return "";
}

impl needs_oauth(auth_type: any) -> bool {
    return login_kind(auth_type) == "oauth";
}

impl validate_model_entry(item: any) -> dict[str, any] | None {
    if not isinstance(item, dict) {
        return None;
    }
    provider = item.get("provider");
    model_id = item.get("modelId");
    display = item.get("displayName");
    if not isinstance(provider, str) or not provider {
        return None;
    }
    if not isinstance(model_id, str) or not model_id {
        return None;
    }
    if not isinstance(display, str) or not display {
        return None;
    }
    return {"provider": provider, "modelId": model_id, "displayName": display};
}

impl filter_providers_by_query(
    providers: list[dict[str, any]], query: str
) -> list[dict[str, any]] {
    if not query {
        return list(providers);
    }
    q = query.lower();
    found: list[dict[str, any]] = [];
    for p in providers {
        if q in str(p.get("id", "")).lower() or q in str(p.get("displayName", "")).lower() {
            found.append(p);
        }
    }
    return found;
}

impl filter_models_by_query(
    models: list[dict[str, any]], query: str, provider_filter: str = ""
) -> list[dict[str, any]] {
    result = models;
    if provider_filter {
        result = [m for m in result if m.get("provider") == provider_filter];
    }
    if query {
        q = query.lower();
        result = [
            m
            for m in result
            if q in str(m.get("modelId", "")).lower()
                or q in str(m.get("displayName", "")).lower()
                or q in str(m.get("provider", "")).lower()
        ];
    }
    return result;
}

impl format_provider_label(item: dict[str, any]) -> str {
    name = item.get("displayName", item.get("id", "unknown"));
    auth_type = item.get("authType", "");
    configured = "✓" if item.get("configured") else " ";
    model_count = item.get("modelCount", 0);
    labels = {"oauth": "OAuth", "api_key": "API Key", "env": "Env"};
    auth_label = labels.get(str(auth_type), str(auth_type));
    return "["
        + configured
        + "] "
        + str(name)
        + " ("
        + auth_label
        + ", "
        + str(model_count)
        + " models)";
}

impl format_model_label(item: dict[str, any]) -> str {
    display = item.get("displayName", item.get("modelId", "unknown"));
    provider = item.get("provider", "");
    model_id = item.get("modelId", "");
    if provider {
        return str(display) + " (" + str(provider) + "/" + str(model_id) + ")";
    }
    return str(display);
}
