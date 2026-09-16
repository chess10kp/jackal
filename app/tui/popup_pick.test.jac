"""Regression tests for the slash-popup tab/enter decision.

The tested function is a VERBATIM replica of tui.overlay._slash_popup_pick
(keep in sync) — the real TUI modules cannot host test annexes yet (see
tui/popup_pick.jac). The wiring being guarded: tui/input.jac's popup branch
must SUBMIT when Enter lands on a candidate identical to the draft.
Completing /model to /model used to be a visual no-op that swallowed the
keypress, so `/model` + Enter appeared dead and the MODEL picker only
opened on a second Enter.
"""

"""Verbatim replica of tui.overlay._slash_popup_pick."""
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
    # input.jac completes whenever `not (key == "enter" and submit)` — tab on
    # an exact match still completes (to itself) and dismisses the popup.
    matches: list[list[str]] = [["/model", ""]];
    (chosen, submit) = _slash_popup_pick(matches, "/model", 0);
    assert chosen == "/model";  # completion target; submit flag ignored for tab
    assert submit;      # input.jac only honors it for enter
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
