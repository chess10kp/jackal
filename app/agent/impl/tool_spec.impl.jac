impl make_tool_spec(
    name: str,
    description: str = "",
    parameters: dict[str, any] = {},
    handler: Callable[[dict[str, any]], str] | None = None,
) -> ToolSpec {
    return ToolSpec(name=name, description=description, parameters=parameters, handler=handler);
}
