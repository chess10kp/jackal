"""fx-style live model catalog (see ~/notes/fx-model-picker.md).

Each PROVIDER_ROUTES entry advertises a static `models` hint list; this
module replaces those hints at picker time with a LIVE fetch of
`{base_url}/models` (OpenAI-compatible `{"data": [{"id": ...}]}` shape),
subject to:

  - a freshness window (fx uses 60 s; `JACKAL_CATALOG_TTL_MS` overrides)
  - keep-last-good: a failed/empty refresh serves the previous catalog
  - static fallback: with no cache at all, the route's `models` hints

The fetch itself never runs for local routes (`base_url` startswith
"local://" — mockllm) and never raises: a catalog problem must degrade to
the static hints, not break `/model`. Picker reads never wait for network I/O;
stale catalogs refresh in a deduplicated background flow.
"""

import os;
import time;
import from .llm_transport { PROVIDER_ROUTES }

glob _CATALOG_REFRESHING: dict[str, bool] = {};

"""Freshness window in milliseconds (fx: provider_versions refresh 60 s)."""
glob CATALOG_TTL_MS: int = 60_000;

"""Hard cap on ids kept from one fetch (fx caps at 128 for codex; gateways
list hundreds). Response order is preserved within the cap."""
glob MAX_CATALOG_MODELS: int = 256;

"""provider -> {"models": list[str], "fetched_ms": int}. Entries are written
only by _merge_catalog_result/refresh_model_catalog."""
glob _CATALOG_CACHE: dict[str, dict[str, any]] = {};


def _now_ms() -> int {
    return int(time.time() * 1000);
}


"""Read the env TTL override once per call (tests and power users both win).
Invalid/negative values fall back to the default window."""
def _ttl_ms() -> int {
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


"""Parse an OpenAI-compatible models payload into a clean id list.

Pure: accepts anything, returns [] for malformed shapes, drops non-string
ids, dedupes preserving first-seen order, caps at MAX_CATALOG_MODELS."""
def _parse_models_payload(payload: any) -> list[str] {
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


"""True when a cache entry is still inside the freshness window. A missing
entry is never fresh; `now_ms`/`ttl_ms` injected for tests."""
def _entry_is_fresh(cached: dict[str, any] | None, now_ms: int, ttl_ms: int) -> bool {
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


"""Merge one fetch outcome into the cache and return what the picker shows.

Semantics (fx parity):
  fetch succeeded (non-empty) -> cache + serve it
  fetch failed/empty          -> serve last-good cache if any
  nothing cached yet          -> serve the static route hints
Pure over its inputs; writes the module cache."""
def _merge_catalog_result(provider: str, fetched: list[str], fallback: list[str], now_ms: int) -> list[str] {
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


"""Static `models` hints for a route ("" provider -> [])."""
def _static_models(route: dict[str, any] | None) -> list[str] {
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


"""True when a route's base_url marks a local/no-network provider."""
def _is_local_route(route: dict[str, any] | None) -> bool {
    if route is None {
        return True;
    }
    base = str(route.get("base_url", ""));
    return base.startswith("local://") or not base;
}


"""GET `{base_url}/models` for one route and parse the payload.

Returns [] on ANY failure (missing credential, HTTP error, timeout, bad
JSON) — callers fall back to cache/static hints. Never raises."""
def _fetch_route_models(route: dict[str, any]) -> list[str] {
    if _is_local_route(route) {
        return [];
    }
    try {
        import httpx;
        base = str(route.get("base_url", ""));
        url = base.rstrip("/") + "/models";
        headers: dict[str, str] = {};
        key_env = str(route.get("key_env", ""));
        api_key = os.environ.get(key_env, "") if key_env else "";
        if api_key {
            headers["Authorization"] = "Bearer " + api_key;
        }
        # Short timeout for background refreshes; picker reads never wait here.
        client_obj: any = httpx.Client(timeout=5.0);
        try {
            r: any = client_obj.get(url, headers=headers);
            if r.status_code != 200 {
                return [];
            }
            return _parse_models_payload(r.json());
        } finally {
            client_obj.close();
        }
    } except Exception {
        return [];
    }
}


"""Return provider catalog immediately: cached ids or static hints. Stale/missing
catalogs refresh in the background; unknown providers get []. Never raises."""
def catalog_models(provider: str) -> list[str] {
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


"""Fire-and-forget warm of every fetchable route. Called from the TUI boot
seam right after credentials are hydrated so `/model` opens with live
catalogs already cached (fx's preload thread, in flow form)."""
def warm_model_catalog() {
    for prov in PROVIDER_ROUTES {
        _schedule_catalog_refresh(str(prov));
    }
}


"""Force-refresh every fetchable route. Returns {provider: model_count}
mirroring what the picker would show (a failed fetch contributes its
cache/static fallback count). Never raises."""
def refresh_model_catalog() -> dict[str, int] {
    counts: dict[str, int] = {};
    for prov in PROVIDER_ROUTES {
        provider = str(prov);
        raw_route: any = PROVIDER_ROUTES[prov];
        route: dict[str, any] = raw_route if isinstance(raw_route, dict) else {};
        if _is_local_route(route) {
            continue;
        }
        fetched = _fetch_route_models(route);
        shown = _merge_catalog_result(
            provider, fetched, _static_models(route), _now_ms()
        );
        counts[provider] = len(shown);
    }
    return counts;
}

def _refresh_one(provider: str) {
    try {
        raw_route: any = PROVIDER_ROUTES.get(provider);
        route: dict[str, any] = raw_route if isinstance(raw_route, dict) else {};
        if not _is_local_route(route) {
            fetched: list[str] = _fetch_route_models(route);
            _merge_catalog_result(provider, fetched, _static_models(route), _now_ms());
        }
    } except Exception {
    } finally {
        _CATALOG_REFRESHING.pop(provider, None);
    }
}

def _schedule_catalog_refresh(provider: str) {
    if _CATALOG_REFRESHING.get(provider, False) {
        return;
    }
    _CATALOG_REFRESHING[provider] = True;
    flow _refresh_one(provider);
}
