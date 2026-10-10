"""Command-line argument parsing for the headless entry (app/main.jac).

Pure string work so it lowers natively and is testable without a session.
"""

import from .modes { DEV_MODES }

glob CLI_VERSION: str = "0.1.0";

glob OUTPUT_FORMATS: list[str] = ["text", "json", "stream-json"];

glob CLI_USAGE: str = (
    "usage: jackal [options] [prompt...]\n"
    "\n"
    "Interactive line REPL by default; pass -p for a one-shot run.\n"
    "\n"
    "options:\n"
    "  -p, --print              run the prompt non-interactively, print the answer, exit\n"
    "                           (prompt from args and/or piped stdin)\n"
    "  --output-format FMT      print-mode output: text (default), json, stream-json\n"
    "  --json                   JSONL protocol on stdio (UI clients)\n"
    "  -m, --model NAME         model, e.g. openrouter/anthropic/claude-sonnet-5\n"
    "  --thinking LEVEL         thinking level (off|minimal|low|medium|high)\n"
    "  --mode MODE              normal | auto-accept | yolo | plan | ask\n"
    "  -c, --continue           resume the most recent session in this directory\n"
    "  -r, --resume ID          resume a saved session by id\n"
    "  --max-turns N            cap tool-loop iterations per prompt (default 30)\n"
    "  -h, --help               show this help\n"
    "  -V, --version            print the version"
);

"""Flags that consume the following argv element."""
glob _VALUE_FLAGS: dict[str, str] = {
    "--output-format": "output_format",
    "-m": "model",
    "--model": "model",
    "--thinking": "thinking",
    "--mode": "mode",
    "-r": "resume",
    "--resume": "resume",
    "--max-turns": "max_turns",
};


"""Default option set: every key parse_cli may fill."""
def default_cli_options() -> dict[str, any] {
    return {
        "print": False,
        "json": False,
        "output_format": "text",
        "model": "",
        "thinking": "",
        "mode": "",
        "continue": False,
        "resume": "",
        "max_turns": 0,
        "help": False,
        "version": False,
        "prompt": "",
        "error": "",
    };
}


"""Parse argv (without the program name). Unknown flags and bad values set
`error`; positional words join into `prompt`. `--` ends flag parsing."""
def parse_cli(argv: list[str]) -> dict[str, any] {
    opts: dict[str, any] = default_cli_options();
    words: list[str] = [];
    i: int = 0;
    n: int = len(argv);
    flags_done: bool = False;
    while i < n {
        arg: str = argv[i];
        i += 1;
        if flags_done or not arg.startswith("-") or arg == "-" {
            words.append(arg);
            continue;
        }
        if arg == "--" {
            flags_done = True;
            continue;
        }
        key: str = arg;
        inline: str | None = None;
        if arg.startswith("--") and "=" in arg {
            eq: int = arg.index("=");
            key = arg[:eq];
            inline = arg[eq + 1:];
        }
        if key in ("-p", "--print") {
            opts["print"] = True;
        } elif key == "--json" {
            opts["json"] = True;
        } elif key in ("-c", "--continue") {
            opts["continue"] = True;
        } elif key in ("-h", "--help") {
            opts["help"] = True;
        } elif key in ("-V", "--version") {
            opts["version"] = True;
        } elif key in _VALUE_FLAGS {
            value: str = "";
            if inline is not None {
                value = inline;
            } elif i < n {
                value = argv[i];
                i += 1;
            } else {
                opts["error"] = "missing value for " + key;
                return opts;
            }
            opts[_VALUE_FLAGS[key]] = value;
        } else {
            opts["error"] = "unknown option: " + arg;
            return opts;
        }
    }
    opts["prompt"] = " ".join(words).strip();
    return _validate(opts);
}


def _validate(opts: dict[str, any]) -> dict[str, any] {
    fmt: str = str(opts["output_format"]);
    if fmt not in OUTPUT_FORMATS {
        opts["error"] = "invalid --output-format: " + fmt + " (text|json|stream-json)";
        return opts;
    }
    mode: str = str(opts["mode"]);
    if mode and mode not in DEV_MODES {
        opts["error"] = "invalid --mode: " + mode + " (" + "|".join(DEV_MODES) + ")";
        return opts;
    }
    raw_turns: any = opts["max_turns"];
    if isinstance(raw_turns, str) {
        turns_str: str = raw_turns;
        if not turns_str.isdigit() or int(turns_str) < 1 {
            opts["error"] = "invalid --max-turns: " + turns_str;
            return opts;
        }
        opts["max_turns"] = int(turns_str);
    }
    if opts["continue"] and opts["resume"] {
        opts["error"] = "--continue and --resume are mutually exclusive";
        return opts;
    }
    if opts["print"] and opts["json"] {
        opts["error"] = "--print and --json are mutually exclusive";
        return opts;
    }
    return opts;
}


"""Combine the argv prompt with piped stdin text (stdin appended after a
blank line, matching `cat file | jackal -p "summarize"`)."""
def combine_prompt(arg_prompt: str, stdin_text: str) -> str {
    piped: str = stdin_text.strip();
    if arg_prompt and piped {
        return arg_prompt + "\n\n" + piped;
    }
    return arg_prompt if arg_prompt else piped;
}
