"""Real LiveShell driven in-process on an emulated terminal (merged with
tui/harness.jac). Every assertion reads the emulated screen."""


test "first frame: header hidden, prompt, terminal modes" {
    h = open_tui();
    try {
        h.wait_for("❯");
        assert h.term.find("● ready") is None, h.dump();
        assert h.term.find("❯") is not None, h.dump();
        assert h.term.alternate_screen and h.term.bracketed_paste, h.dump();
        assert h.term.title.startswith("Jackal"), h.term.title;
        for line in h.term.viewport() {
            assert len(line) <= 100, h.dump();
        }
    } finally {
        h.close();
    }
}


test "typing echoes in the editor and backspace leaves no residue" {
    h = open_tui();
    try {
        h.type_text("hello there");
        h.wait_for("hello there");
        for _ in range(len("hello there")) { h.press("backspace"); }
        h.wait_gone("hello there");
        assert "hello" not in h.screen(), h.dump();
        assert h.calls() == [];
    } finally {
        h.close();
    }
}


test "submit streams the reply into the transcript" {
    h = open_tui(script=[{"text": "streamed reply from mock"}]);
    try {
        h.type_text("hi jackal");
        h.press("enter");
        h.wait_for("streamed reply from mock");
        h.wait_idle();
        txt = h.screen();
        assert "◆ you" in txt and "hi jackal" in txt, h.dump();
        assert "◇ jackal" in txt, h.dump();
        calls = h.calls();
        assert len(calls) == 1 and calls[0]["last"]["content"] == "hi jackal", h.dump();
    } finally {
        h.close();
    }
}


test "approval modal: y runs the tool" {
    h = open_tui(script=[
        {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "a.txt", "content": "A"}}]},
        {"text": "wrote a.txt"},
    ]);
    try {
        h.type_text("make a.txt");
        h.press("enter");
        h.wait_for("approve");
        assert not h.exists("a.txt");
        h.press("y");
        h.wait_for("wrote a.txt");
        h.wait_idle();
        assert h.read("a.txt") == "A";
    } finally {
        h.close();
    }
}


test "approval modal: n denies and the model is told" {
    h = open_tui(script=[
        {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "b.txt", "content": "B"}}]},
        {"text": "ok, skipped"},
    ]);
    try {
        h.type_text("make b.txt");
        h.press("enter");
        h.wait_for("approve");
        h.press("n");
        h.wait_for("ok, skipped");
        h.wait_idle();
        assert not h.exists("b.txt");
        assert "denied" in h.calls()[1]["last"]["content"], h.dump();
    } finally {
        h.close();
    }
}


test "yolo mode runs tools without a modal" {
    h = open_tui(
        files={"n.txt": "alpha\n"},
        script=[
            {"text": "", "tool_calls": [{"name": "edit_file", "args": {"path": "n.txt", "old_text": "alpha", "new_text": "beta"}}]},
            {"text": "edited"},
        ],
        mode="yolo",
    );
    try {
        h.wait_for("YOLO");
        h.type_text("edit it");
        h.press("enter");
        h.wait_for("edited");
        h.wait_idle();
        assert h.read("n.txt") == "beta\n";
    } finally {
        h.close();
    }
}


test "slash commands render output and shift+tab cycles the mode badge" {
    h = open_tui();
    try {
        h.type_text("/help");
        h.press("enter");
        h.wait_for("/compact");
        h.press("shift+tab");
        h.wait_for("AUTO");
        h.type_text("/mode plan");
        h.press("enter");
        h.wait_for("PLAN");
        assert h.calls() == [];
    } finally {
        h.close();
    }
}


test "resize reflows within the new bounds" {
    h = open_tui(script=[{"text": "a fairly long answer line that will need to wrap once the terminal becomes narrow"}]);
    try {
        h.type_text("q");
        h.press("enter");
        h.wait_for("fairly long");
        h.wait_idle();
        h.resize(50, 20);
        h.wait_for("❯");
        for line in h.term.viewport() {
            assert len(line) <= 50, h.dump();
        }
        assert len(h.term.viewport()) == 20;
        assert "narrow" in h.screen(), h.dump();
    } finally {
        h.close();
    }
}


test "esc quits and close restores the terminal" {
    h = open_tui();
    try {
        h.press("esc");
        h.step(3);
        assert not h.app.running, h.dump();
    } finally {
        h.close();
    }
    assert not h.term.alternate_screen;
    assert not h.term.bracketed_paste;
    assert h.term.cursor_visible;
}
