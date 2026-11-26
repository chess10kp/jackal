import from agent.llm { PROVIDER_ROUTES, provider_for, credential_error, routed_model_id }

test "routing seam is the real agent.llm table" {
    assert provider_for("deepseek/deepseek-chat") == "deepseek";
    assert provider_for("deepseek-chat") == "openai_compat";
}

def _model_completion_candidates(prefix: str) -> list[list[str]] {
    p = prefix.strip().lower();
    pool: list[str] = [];
    seen: dict[str, bool] = {};
    for prov in PROVIDER_ROUTES {
        route: any = PROVIDER_ROUTES[prov];
        meta: dict[str, any] = route if isinstance(route, dict) else {};
        for m in (meta.get("models", []) or []) {
            mid = routed_model_id(str(prov), str(m));
            if mid not in seen {
                seen[mid] = True;
                pool.append(mid);
            }
        }
    }
    filtered: list[str] = [];
    if not p {
        filtered = pool[:8];
    } else {
        for mid in pool {
            if p in mid.lower() {
                filtered.append(mid);
                if len(filtered) >= 8 {
                    break;
                }
            }
        }
    }
    out: list[list[str]] = [];
    for mid in filtered {
        prov = provider_for(mid);
        desc = "";
        route: any = PROVIDER_ROUTES.get(prov);
        if isinstance(route, dict) {
            desc = str(route.get("description", "") or "");
        }
        out.append(["/model " + mid, desc]);
    }
    return out;
}

test "every advertised id routes to its advertising provider" {
    for prov in PROVIDER_ROUTES {
        route: any = PROVIDER_ROUTES[prov];
        meta: dict[str, any] = route if isinstance(route, dict) else {};
        for m in (meta.get("models", []) or []) {
            mname = str(m);
            expected = routed_model_id(str(prov), mname);
            assert provider_for(expected) == str(prov);
            cerr = credential_error(expected);
            key_env = str(meta.get("key_env", "") or "");
            if key_env and cerr {
                assert key_env in cerr;
            }
        }
    }
}

test "candidate labels are complete /model commands" {
    cands: list[list[str]] = _model_completion_candidates("");
    assert len(cands) > 0;
    for c in cands {
        label = str(c[0]);
        assert label.startswith("/model ");
        mid = label[len("/model "):];
        assert mid != "";
        assert " " not in mid;
        assert provider_for(mid) in PROVIDER_ROUTES;
    }
}

test "deepseek rows carry the provider prefix (the reported misroute)" {
    cands: list[list[str]] = _model_completion_candidates("deepseek");
    found = False;
    for c in cands {
        label = str(c[0]);
        if label == "/model deepseek/deepseek-chat" {
            found = True;
            assert provider_for("deepseek/deepseek-chat") == "deepseek";
        }
    }
    assert found;
}

test "openrouter rows keep their nested catalog id intact" {
    cands: list[list[str]] = _model_completion_candidates("claude-sonnet");
    found = False;
    for c in cands {
        label = str(c[0]);
        if label == "/model openrouter/anthropic/claude-sonnet-5" {
            found = True;
            assert provider_for("openrouter/anthropic/claude-sonnet-5") == "openrouter";
        }
    }
    assert found;
}

test "bare ids that already route correctly stay bare" {
    mock_found = False;
    for c in _model_completion_candidates("mock") {
        if str(c[0]) == "/model mock" {
            mock_found = True;
            assert provider_for("mock") == "mock";
        }
    }
    assert mock_found;

    gpt_found = False;
    for c in _model_completion_candidates("gpt-4o") {
        if str(c[0]) == "/model gpt-4o" {
            gpt_found = True;
            assert provider_for("gpt-4o") == "openai_compat";
        }
    }
    assert gpt_found;
}

test "prefix filters by substring and caps at 8" {
    cands: list[list[str]] = _model_completion_candidates("zzz-no-such-model");
    assert len(cands) == 0;
    wide: list[list[str]] = _model_completion_candidates("");
    assert len(wide) <= 8;
}
