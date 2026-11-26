obj RegisteredTool {
    has name: str = "",
        description: str = "",
        parameters: dict[str, any] = {},
        origin: str = "native",
        extension_id: str = "",
        handler: Callable[[dict[str, any]], str] | None = None;
}

obj ToolRegistry {
    has tools: dict[str, RegisteredTool] = {};
}

def create_registry -> ToolRegistry;
def register_native(
    reg: ToolRegistry,
    name: str,
    description: str,
    parameters: dict[str, any],
    handler: Callable[[dict[str, any]], str],
) -> RegisteredTool;
def register_js(
    reg: ToolRegistry, name: str, description: str, parameters: dict[str, any], extension_id: str
) -> RegisteredTool;
def register_native_spec(reg: ToolRegistry, spec: ToolSpec) -> RegisteredTool;

def get_tool(reg: ToolRegistry, name: str) -> RegisteredTool | None;

def unregister(reg: ToolRegistry, name: str) -> bool;
def unregister_extension(reg: ToolRegistry, extension_id: str) -> int;
def as_tool_specs(reg: ToolRegistry) -> list[ToolSpec];
def openai_tools(reg: ToolRegistry) -> list[dict[str, any]];
def invoke(reg: ToolRegistry, name: str, args: dict[str, any], bridge: any = None) -> str;
