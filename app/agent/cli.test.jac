"""CLI argument parsing tests (merged with agent/cli.jac by stem)."""


test "no args yields defaults" {
    opts = parse_cli([]);
    assert opts["error"] == "";
    assert not opts["print"];
    assert opts["output_format"] == "text";
    assert opts["prompt"] == "";
}


test "print mode joins positional words into the prompt" {
    opts = parse_cli(["-p", "fix", "the", "bug"]);
    assert opts["print"];
    assert opts["prompt"] == "fix the bug";
}


test "value flags accept separate and inline forms" {
    opts = parse_cli(["--model", "openrouter/x", "--mode=yolo", "-r", "abc", "--max-turns", "5"]);
    assert opts["error"] == "";
    assert opts["model"] == "openrouter/x";
    assert opts["mode"] == "yolo";
    assert opts["resume"] == "abc";
    assert opts["max_turns"] == 5;
}


test "double dash ends flag parsing" {
    opts = parse_cli(["-p", "--", "--not-a-flag"]);
    assert opts["error"] == "";
    assert opts["prompt"] == "--not-a-flag";
}


test "invalid values and unknown flags set error" {
    assert parse_cli(["--bogus"])["error"].startswith("unknown option");
    assert parse_cli(["--model"])["error"].startswith("missing value");
    assert parse_cli(["--mode", "turbo"])["error"].startswith("invalid --mode");
    assert parse_cli(["--output-format", "xml"])["error"].startswith("invalid --output-format");
    assert parse_cli(["--max-turns", "0"])["error"].startswith("invalid --max-turns");
    assert parse_cli(["-c", "-r", "x"])["error"] != "";
    assert parse_cli(["-p", "--json"])["error"] != "";
}


test "help and version flags" {
    assert parse_cli(["-h"])["help"];
    assert parse_cli(["--version"])["version"];
}


test "combine_prompt appends piped stdin" {
    assert combine_prompt("summarize", "file body\n") == "summarize\n\nfile body";
    assert combine_prompt("", "only stdin\n") == "only stdin";
    assert combine_prompt("only arg", "  ") == "only arg";
}
