"""Regression tests for the MODEL completion window's advertised ids.

The builder is a near-verbatim replica of
tui.overlay._model_completion_candidates (keep in sync) — real TUI modules
cannot host test annexes yet (see tui/model_picker_ids.jac). The one
deliberate difference: the replica feeds the routes' STATIC hint lists
instead of agent.model_catalog's live fetches (no network in tests); live
ids flow through the same routed_model_id seam, which is what these tests
guard. The per-provider "· last" and active-model pool entries are also
omitted (presentation-only, needs the heavy agent.session import).
Everything BEHIND the replica is real: agent.llm's PROVIDER_ROUTES /
provider_for / routed_model_id / credential_error own routing, and
agent.model_catalog owns the live catalog source.

The guarded invariants: every candidate id must round-trip provider_for
to the provider that advertises it, and every candidate label must be a
complete "/model <id>" command (the completion window replaces the whole
draft with the label, so the label IS the command). The old MODEL picker
used to advertise bare catalog ids ("deepseek-chat"), which misroute to
openai_compat — wrong endpoint and confusing "set OPENAI_API_KEY"
credential errors even for users logged into deepseek/openrouter via
auth.json.
"""

import from agent.llm {
    PROVIDER_ROUTES, provider_for, credential_error, routed_model_id
}

# the real symbols must resolve: the replica's invariant is only
# meaningful against the live routing table
test "routing seam is the real agent.llm table" {
    assert provider_for("deepseek/deepseek-chat") == "deepseek";
    assert provider_for("deepseek-chat") == "openai_compat";
}


"""Replica of tui.overlay._model_completion_candidates minus the live
catalog fetches (network) and model_preferences/active-model pool entries
(heavy agent.session import). The guarded id/label construction is
reproduced exactly."""
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
            # The credential check for the advertised id must name the
            # advertising provider's env var, never a fallthrough provider.
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
        # stripping the command word must yield an id that routes back to
        # a REAL provider (label == command invariant; the fallthrough
        # openai_compat mapping counts, bare unknown ids would not resolve)
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
            # Label carries one provider prefix so make_transport strips it
            # back to the wire id.
            assert provider_for("openrouter/anthropic/claude-sonnet-5") == "openrouter";
        }
    }
    assert found;
}


test "bare ids that already route correctly stay bare" {
    # targeted prefixes: the unfiltered pool is capped at 8 and both bare
    # ids sit past the cut, so exercise them directly
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
