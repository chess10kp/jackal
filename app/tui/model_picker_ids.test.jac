"""Regression tests for the MODEL picker's advertised ids.

The builder is a near-verbatim replica of
tui.picker_actions._model_picker_entries (keep in sync) — real TUI modules
cannot host test annexes yet (see tui/model_picker_ids.jac). The one
deliberate difference: the replica feeds the routes' STATIC hint lists
instead of agent.model_catalog's live fetches (no network in tests); live
ids flow through the same routed_model_id seam, which is what these tests
guard. Everything BEHIND the replica is real: agent.llm's PROVIDER_ROUTES /
provider_for / routed_model_id / credential_error own routing, and
agent.model_catalog owns the live catalog source.

The guarded invariant: every advertised row id must round-trip provider_for
to the provider that advertises it. The picker used to advertise bare
catalog ids ("deepseek-chat"), which misroute to openai_compat — wrong
endpoint and confusing "set OPENAI_API_KEY" credential errors even for
users logged into deepseek/openrouter via auth.json.
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


"""Replica of tui.picker_actions._model_picker_entries minus the
model_preferences "· last" rows (presentation-only, needs the heavy
agent.session import). The guarded advertised-id logic is reproduced
exactly."""
def _model_picker_entries() -> dict {
    rows: list[str] = [];
    ids: list[str] = [];
    prefs: dict = {};
    for prov in PROVIDER_ROUTES {
        route = PROVIDER_ROUTES[prov];
        meta: any = route if isinstance(route, dict) else {};
        desc = str(meta.get("description", "") or "");
        header = "── " + str(prov);
        if desc {
            header += " — " + desc;
        }
        rows.append(header + " ──");
        ids.append("__header__");
        for m in (meta.get("models", []) or []) {
            mname = str(m);
            rows.append("  " + mname);
            ids.append(routed_model_id(str(prov), mname));
        }
    }
    return {"rows": rows, "ids": ids};
}


test "every advertised id routes to its advertising provider" {
    entries = _model_picker_entries();
    rows: list = list(entries["rows"]);
    ids: list = list(entries["ids"]);
    assert len(rows) == len(ids);
    for prov in PROVIDER_ROUTES {
        route: any = PROVIDER_ROUTES[prov];
        meta: dict = route if isinstance(route, dict) else {};
        for m in (meta.get("models", []) or []) {
            mname = str(m);
            expected = routed_model_id(str(prov), mname);
            assert expected in ids;
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

test "deepseek rows carry the provider prefix (the reported misroute)" {
    entries = _model_picker_entries();
    rows: list = list(entries["rows"]);
    ids: list = list(entries["ids"]);
    found = False;
    for i in range(len(rows)) {
        if str(rows[i]) == "  deepseek-chat" {
            found = True;
            assert str(ids[i]) == "deepseek/deepseek-chat";
            assert provider_for(str(ids[i])) == "deepseek";
        }
    }
    assert found;
}

test "openrouter rows keep their nested catalog id intact" {
    entries = _model_picker_entries();
    rows: list = list(entries["rows"]);
    ids: list = list(entries["ids"]);
    found = False;
    for i in range(len(rows)) {
        if str(rows[i]) == "  anthropic/claude-sonnet-5" {
            found = True;
            # Label stays the bare catalog name; the id gains one provider
            # prefix so make_transport strips it back to the wire id.
            assert str(ids[i]) == "openrouter/anthropic/claude-sonnet-5";
        }
    }
    assert found;
}

test "bare ids that already route correctly stay bare" {
    entries = _model_picker_entries();
    rows: list = list(entries["rows"]);
    ids: list = list(entries["ids"]);
    for i in range(len(rows)) {
        if str(rows[i]) == "  mock" {
            assert str(ids[i]) == "mock";
        }
        if str(rows[i]) == "  gpt-4o" {
            assert str(ids[i]) == "gpt-4o";
        }
    }
}
