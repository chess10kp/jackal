"""EmulatedTerminal (pyte-backed) fidelity tests (merged with emulated_terminal.jac)."""


test "cursor addressing, erase, and trailing trim" {
    t = EmulatedTerminal(20, 4);
    t.write("hello world");
    t.write("\x1b[1;7H\x1b[K");
    assert t.viewport()[0] == "hello";
    t.write("\x1b[3;5Hxy");
    assert t.viewport()[2] == "    xy";
    assert t.cursor() == (6, 2);
}


test "wrapping and scrollback" {
    t = EmulatedTerminal(10, 3, 100);
    for i in range(6) {
        t.write("line" + str(i) + "\r\n");
    }
    vp = t.viewport();
    assert vp[0] == "line4" and vp[1] == "line5";
    buf = t.scroll_buffer();
    assert buf[0] == "line0";
    t.write("\x1b[2J\x1b[H" + "abcdefghijKL");
    assert t.viewport()[0] == "abcdefghij";
    assert t.viewport()[1] == "KL";
}


test "styles are readable per cell" {
    t = EmulatedTerminal(20, 2);
    t.write("\x1b[1;31mR\x1b[0m\x1b[7mV\x1b[0mn");
    r = t.cell(0, 0);
    assert r["char"] == "R" and r["bold"] and r["fg"] == "red";
    assert t.cell(0, 1)["reverse"];
    assert not t.cell(0, 2)["bold"];
}


test "wide characters take two cells" {
    t = EmulatedTerminal(10, 2);
    t.write("界x");
    assert t.cursor() == (3, 0);
    assert t.viewport()[0].startswith("界");
}


test "mode flags track start and stop" {
    t = EmulatedTerminal(20, 4);
    t.start();
    assert t.alternate_screen and t.bracketed_paste and not t.cursor_visible;
    t.write("\x1b]0;my title\x07");
    assert t.title == "my title";
    t.stop();
    assert not t.alternate_screen and not t.bracketed_paste and t.cursor_visible;
    assert t.restored;
}


test "input queue, keys, paste, resize" {
    t = EmulatedTerminal(20, 4);
    t.send_input("a");
    t.send_key("enter");
    t.send_key("shift+tab");
    t.send_paste("p");
    assert t.poll_input() == "a";
    assert t.poll_input() == "\r";
    assert t.poll_input() == "\x1b[Z";
    assert t.poll_input() == "\x1b[200~p\x1b[201~";
    assert t.poll_input() == "";
    t.resize(30, 6);
    assert t.size() == (30, 6);
    assert len(t.viewport()) == 6;
    assert t.find("zzz") is None;
    t.write("\x1b[2;3Hneedle");
    assert t.find("needle") == (1, 2);
    assert t.line_with("needle") == "  needle";
}
