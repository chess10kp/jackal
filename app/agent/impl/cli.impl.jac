impl user_argv(raw: list[str]) -> list[str] {
    start: int = 1;
    for i in range(len(raw)) {
        a: str = raw[i];
        if a.endswith("main.jac") or a.endswith("main.py") or a == "main" {
            start = i + 1;
            break;
        }
    }
    out: list[str] = list(raw[start:]);
    if out and out[0] == "--" {
        out = out[1:];
    }
    return out;
}

impl default_cli_options -> dict[str, any] {
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

impl parse_cli(argv: list[str]) -> dict[str, any] {
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

impl _validate(opts: dict[str, any]) -> dict[str, any] {
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

impl combine_prompt(arg_prompt: str, stdin_text: str) -> str {
    piped: str = stdin_text.strip();
    if arg_prompt and piped {
        return arg_prompt + "\n\n" + piped;
    }
    return arg_prompt or piped;
}
