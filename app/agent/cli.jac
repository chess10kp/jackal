glob CLI_VERSION: str = "0.1.0";

glob OUTPUT_FORMATS: list[str] = ["text", "json", "stream-json"];

glob CLI_USAGE: str = ("usage: jackal [options] [prompt...]\n"
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
    "  -V, --version            print the version");

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
def user_argv(raw: list[str]) -> list[str];
def default_cli_options -> dict[str, any];
def parse_cli(argv: list[str]) -> dict[str, any];

def _validate(opts: dict[str, any]) -> dict[str, any];
def combine_prompt(arg_prompt: str, stdin_text: str) -> str;
