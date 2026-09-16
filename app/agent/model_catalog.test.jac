"""Tests for agent/model_catalog.jac (same-stem annex, merged with the
base module at test time - no import of the own stem).

Covers the pure catalog pipeline: payload parsing, freshness window,
merge/fallback semantics, static hints, local-route detection, and the
provider-facing catalog_models dispatch. Network I/O (_fetch_route_models,
refresh_model_catalog, warm_model_catalog) is deliberately NOT exercised —
the pure seams around it are.
"""

# ── _parse_models_payload ────────────────────────────────────────────────────

test "parse extracts string ids in order and dedupes" {
    payload = {
        "object": "list",
        "data": [
            {"id": "openai/gpt-5", "created": 1},
            {"id": "anthropic/claude-sonnet-5", "created": 2},
            {"id": "openai/gpt-5"},  # duplicate, dropped
            {"id": "zai/glm-5"},
        ],
    };
    assert _parse_models_payload(payload) == [
        "openai/gpt-5", "anthropic/claude-sonnet-5", "zai/glm-5"
    ];
}

test "parse rejects malformed payloads and bad ids" {
    assert _parse_models_payload(None) == [];
    assert _parse_models_payload([{"id": "x"}]) == [];
    assert _parse_models_payload({}) == [];
    assert _parse_models_payload({"data": "nope"}) == [];
    assert _parse_models_payload({"data": [42, {"nope": 1}, None]}) == [];
    assert _parse_models_payload({"data": [{"id": ""}, {"id": 7}]}) == [];
}

test "parse caps at MAX_CATALOG_MODELS" {
    data = [];
    for i in range(MAX_CATALOG_MODELS + 50) {
        data.append({"id": "m" + str(i)});
    }
    out = _parse_models_payload({"data": data});
    assert len(out) == MAX_CATALOG_MODELS;
    assert out[0] == "m0";
}

# ── _entry_is_fresh ──────────────────────────────────────────────────────────

test "freshness needs a nonempty entry inside the window" {
    assert not _entry_is_fresh(None, 1_000_000, 60_000);
    assert not _entry_is_fresh({"models": ["a"], "fetched_ms": 0}, 1_000_000, 60_000);
    assert not _entry_is_fresh({"models": [], "fetched_ms": 999_000}, 1_000_000, 60_000);
    assert not _entry_is_fresh(
        {"models": ["a"], "fetched_ms": 999_000}, 1_060_000, 60_000
    );  # exactly at the boundary is stale
    assert _entry_is_fresh(
        {"models": ["a"], "fetched_ms": 999_000}, 1_058_999, 60_000
    );
}

# ── _merge_catalog_result ────────────────────────────────────────────────────

test "successful fetch is cached and served" {
    _CATALOG_CACHE.clear();
    now = 1_000_000;
    shown = _merge_catalog_result("prov_a", ["x", "y"], ["hint"], now);
    assert shown == ["x", "y"];
    cached = _CATALOG_CACHE["prov_a"];
    assert cached["models"] == ["x", "y"];
    assert cached["fetched_ms"] == now;
}

test "failed fetch serves last-good cache over static hints" {
    _CATALOG_CACHE.clear();
    _CATALOG_CACHE["prov_b"] = {"models": ["old"], "fetched_ms": 1_000};
    shown = _merge_catalog_result("prov_b", [], ["hint"], 999_999);
    assert shown == ["old"];
    # Failure does not overwrite the last-good entry.
    assert _CATALOG_CACHE["prov_b"]["fetched_ms"] == 1_000;
}

test "failed fetch with no cache serves static hints" {
    _CATALOG_CACHE.clear();
    shown = _merge_catalog_result("prov_c", [], ["hint1", "hint2"], 5);
    assert shown == ["hint1", "hint2"];
    assert "prov_c" not in _CATALOG_CACHE;
}

# ── static hints + local routes ──────────────────────────────────────────────

test "static models filter non-strings and handle missing routes" {
    assert _static_models(None) == [];
    assert _static_models({}) == [];
    assert _static_models({"models": ["a", 3, None, "b"]}) == ["a", "b"];
    assert _static_models({"models": "nope"}) == [];
}

test "local route detection covers local:// empty and missing routes" {
    assert _is_local_route(None);
    assert _is_local_route({});
    assert _is_local_route({"base_url": "local://mockllm"});
    assert not _is_local_route({"base_url": "https://api.example.com/v1"});
}

# ── catalog_models dispatch (no network: local/unknown providers only) ──────

test "mock provider serves static hints without fetching" {
    _CATALOG_CACHE.clear();
    assert catalog_models("mock") == ["mock"];
    assert "mock" not in _CATALOG_CACHE;
}

test "unknown provider serves empty without fetching" {
    _CATALOG_CACHE.clear();
    assert catalog_models("not-a-provider") == [];
}

# ── TTL env override ────────────────────────────────────────────────────────

test "ttl env override validates input" {
    old = os.environ.get("JACKAL_CATALOG_TTL_MS", None);
    try {
        os.environ["JACKAL_CATALOG_TTL_MS"] = "";
        assert _ttl_ms() == CATALOG_TTL_MS;
        os.environ["JACKAL_CATALOG_TTL_MS"] = "garbage";
        assert _ttl_ms() == CATALOG_TTL_MS;
        os.environ["JACKAL_CATALOG_TTL_MS"] = "-5";
        assert _ttl_ms() == CATALOG_TTL_MS;
        os.environ["JACKAL_CATALOG_TTL_MS"] = "120000";
        assert _ttl_ms() == 120000;
    } finally {
        if old is None {
            os.environ.pop("JACKAL_CATALOG_TTL_MS", None);
        } else {
            os.environ["JACKAL_CATALOG_TTL_MS"] = old;
        }
    }
}
