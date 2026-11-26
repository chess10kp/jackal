glob MAX_TOOL_RESULT: int = 50_000,
     MAX_SEARCH_RESULTS: int = 100;

obj ToolSpec {
    has name: str,
        description: str = "",
        parameters: dict[str, any] = {},
        handler: Callable[[dict[str, any]], str] | None = None;
}

def make_tool_spec(
    name: str,
    description: str = "",
    parameters: dict[str, any] = {},
    handler: Callable[[dict[str, any]], str] | None = None,
) -> ToolSpec;
