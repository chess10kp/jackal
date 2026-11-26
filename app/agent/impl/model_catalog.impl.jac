impl _now_ms -> int {
    return int(time.time() * 1000);
}

impl _ttl_ms -> int {
    raw = os.environ.get("JACKAL_CATALOG_TTL_MS", "");
    if not raw {
        return CATALOG_TTL_MS;
    }
    try {
        val = int(raw);
    } except ValueError {
        return CATALOG_TTL_MS;
    }
    if val < 0 {
        return CATALOG_TTL_MS;
    }
    return val;
}

impl _parse_models_payload(payload: any) -> list[str] {
    out: list[str] = [];
    if not isinstance(payload, dict) {
        return out;
    }
    data: any = payload.get("data");
    if not isinstance(data, list) {
        return out;
    }
    for row in data {
        if len(out) >= MAX_CATALOG_MODELS {
            break;
        }
        if not isinstance(row, dict) {
            continue;
        }
        mid: any = row.get("id");
        if not isinstance(mid, str) or not mid {
            continue;
        }
        if mid in out {
            continue;
        }
        out.append(mid);
    }
    return out;
}

impl _entry_is_fresh(cached: dict[str, any] | None, now_ms: int, ttl_ms: int) -> bool {
    if cached is None {
        return False;
    }
    fetched: any = cached.get("fetched_ms", 0);
    if not isinstance(fetched, int) or fetched <= 0 {
        return False;
    }
    models: any = cached.get("models");
    if not isinstance(models, list) or not models {
        return False;
    }
    return now_ms - fetched < ttl_ms;
}

impl _merge_catalog_result(
    provider: str, fetched: list[str], fallback: list[str], now_ms: int
) -> list[str] {
    if fetched {
        _CATALOG_CACHE[provider] = {"models": list(fetched), "fetched_ms": now_ms};
        return list(fetched);
    }
    stale: any = _CATALOG_CACHE.get(provider);
    if isinstance(stale, dict) {
        models: any = stale.get("models");
        if isinstance(models, list) and models {
            return list(models);
        }
    }
    return list(fallback);
}

impl _static_models(route: dict[str, any] | None) -> list[str] {
    if route is None {
        return [];
    }
    raw: any = route.get("models", []);
    if not isinstance(raw, list) {
        return [];
    }
    out: list[str] = [];
    for m in raw {
        if isinstance(m, str) and m {
            out.append(m);
        }
    }
    return out;
}

impl _is_local_route(route: dict[str, any] | None) -> bool {
    if route is None {
        return True;
    }
    base = str(route.get("base_url", ""));
    return base.startswith("local://") or not base;
}

impl _fetch_route_models(route: dict[str, any]) -> list[str] {
    if _is_local_route(route) {
        return [];
    }
    try {
        base = str(route.get("base_url", ""));
        url = base.rstrip("/") + "/models";
        headers: dict[str, str] = {};
        key_env = str(route.get("key_env", ""));
        api_key = os.environ.get(key_env, "") if key_env else "";
        if api_key {
            headers["Authorization"] = "Bearer " + api_key;
        }
        req = urllib.request.Request(url, headers=headers);
        r: any = urllib.request.urlopen(req, timeout=5.0);
        try {
            if int(r.status) != 200 {
                return [];
            }
            return _parse_models_payload(json.loads(r.read().decode("utf-8")));
        } finally {
            r.close();
        }
    } except Exception {
        return [];
    }
}

impl catalog_models(provider: str) -> list[str] {
    route: dict[str, any] | None = None;
    raw_route: any = PROVIDER_ROUTES.get(provider);
    if isinstance(raw_route, dict) {
        route = raw_route;
    }
    if (_is_local_route(route)) {
        return _static_models(route);
    }
    cached: any = _CATALOG_CACHE.get(provider);
    models: any = cached.get("models") if isinstance(cached, dict) else None;
    if (isinstance(models, list) and models) {
        if not _entry_is_fresh(cached, _now_ms(), _ttl_ms()) {
            _schedule_catalog_refresh(provider);
        }
        return list(models);
    }
    _schedule_catalog_refresh(provider);
    return _static_models(route);
}

impl warm_model_catalog {
    for prov in PROVIDER_ROUTES {
        _schedule_catalog_refresh(str(prov));
    }
}

impl refresh_model_catalog -> dict[str, int] {
    counts: dict[str, int] = {};
    for prov in PROVIDER_ROUTES {
        provider = str(prov);
        raw_route: any = PROVIDER_ROUTES[prov];
        route: dict[str, any] = raw_route if isinstance(raw_route, dict) else {};
        if _is_local_route(route) {
            continue;
        }
        fetched = _fetch_route_models(route);
        shown = _merge_catalog_result(provider, fetched, _static_models(route), _now_ms());
        counts[provider] = len(shown);
    }
    return counts;
}

impl _refresh_one(provider: str) {
    try {
        raw_route: any = PROVIDER_ROUTES.get(provider);
        route: dict[str, any] = raw_route if isinstance(raw_route, dict) else {};
        if not _is_local_route(route) {
            fetched: list[str] = _fetch_route_models(route);
            _merge_catalog_result(provider, fetched, _static_models(route), _now_ms());
        }
    } except Exception {} finally {
        _CATALOG_REFRESHING.pop(provider, None);
    }
}

impl _schedule_catalog_refresh(provider: str) {
    if _CATALOG_REFRESHING.get(provider, False) {
        return;
    }
    _CATALOG_REFRESHING[provider] = True;
    flow _refresh_one(provider);
}
