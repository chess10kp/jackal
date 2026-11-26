def _slash_popup_pick(matches: list[list[str]], draft: str, sel: int) -> tuple[str, bool] {
    count = len(matches);
    idx = int(sel);
    if idx >= count {
        idx = count - 1;
    }
    if idx < 0 {
        idx = 0;
    }
    chosen = str(matches[idx][0]);
    return (chosen, chosen == draft.strip());
}

test "exact match must submit, not re-complete" {
    matches: list[list[str]] = [["/model", "show or set the model"]];
    (chosen, submit) = _slash_popup_pick(matches, "/model", 0);
    assert chosen == "/model";
    assert submit;
}

test "prefix match must complete" {
    matches: list[list[str]] = [["/model", "show or set the model"]];
    (chosen, submit) = _slash_popup_pick(matches, "/mod", 0);
    assert chosen == "/model";
    assert not submit;
}

test "tab decision is unaffected by the submit rule" {
    matches: list[list[str]] = [["/model", ""]];
    (chosen, submit) = _slash_popup_pick(matches, "/model", 0);
    assert chosen == "/model";
    assert submit;
}

test "stale selection clamps into range" {
    matches: list[list[str]] = [["/checkpoint", "create"], ["/checkpoints", "browse"]];
    (chosen_hi, submit_hi) = _slash_popup_pick(matches, "/checkpoints", 9);
    assert chosen_hi == "/checkpoints";
    assert submit_hi;
    (chosen_lo, submit_lo) = _slash_popup_pick(matches, "/checkpoint", -3);
    assert chosen_lo == "/checkpoint";
    assert submit_lo;
}

test "exact match among several candidates still submits" {
    matches: list[list[str]] = [["/checkpoint", "create"], ["/checkpoints", "browse"]];
    (chosen, submit) = _slash_popup_pick(matches, "/checkpoint", 0);
    assert chosen == "/checkpoint";
    assert submit;
}

def _popup_suppressed(raw: str, dismissed: str) -> bool {
    return raw == dismissed;
}

test "completed /model must not suppress the argument window" {
    assert _popup_suppressed("/model", "/model");
    assert not _popup_suppressed("/model ", "/model");
}

test "esc hides the exact draft and typing reopens" {
    assert _popup_suppressed("/model ", "/model ");
    assert not _popup_suppressed("/model c", "/model ");
}
