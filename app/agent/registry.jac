"""Tool registry - native + js origins for the owned ReAct loop.

One lookup surface so Cordis `tools.*` fibers and the Pi JS host can both
contribute without a second source of truth. Native tools keep local handlers;
js tools carry schema only and dispatch through a PluginBridge.
"""

import from .tool_spec {
    ToolSpec,
    make_tool_spec,
}
import from .logging { log_exception }
import from .plugin_bridge_model { PluginBridge }
import from .plugin_bridge_core { invoke_tool }


obj:pub RegisteredTool {
    has name: str = "",
        description: str = "",
        parameters: dict[str, any] = {},
        origin: str = "native",
        extension_id: str = "",
        # Native handlers receive one decoded argument dictionary.
        handler: Callable[[dict[str, any]], str] | None = None;
}


obj:pub ToolRegistry {
    has tools: dict[str, RegisteredTool] = {};
}


glob _registry_handles: dict[int, ToolRegistry] = {},
     _next_registry_handle: int = 1;


def create_registry() -> ToolRegistry {
    return ToolRegistry();
}


"""Create a scalar handle for a registry owned by this module.

The handle keeps concrete registry layouts inside this module across native
unit boundaries. Callers exchange only an integer and data transfer values.
"""
def:pub create_registry_handle() -> int {
    handle: int = _next_registry_handle;
    _next_registry_handle += 1;
    _registry_handles[handle] = ToolRegistry();
    return handle;
}


def _registry_for_handle(handle: int) -> ToolRegistry {
    reg: ToolRegistry | None = _registry_handles.get(handle);
    if reg is None {
        raise ValueError("unknown tool registry handle");
    }
    return reg;
}


"""Resolve a registry handle for native cross-module APIs.

The returned object remains owned by this module; callers use it opaquely.
"""
def:pub registry_from_handle(handle: int) -> ToolRegistry {
    return _registry_for_handle(handle);
}


"""Register or replace a native tool with a local dict-ABI handler."""
def register_native(
    reg: ToolRegistry,
    name: str,
    description: str,
    parameters: dict[str, any],
    handler: Callable[[dict[str, any]], str],
) -> RegisteredTool {
    if not name {
        raise ValueError("tool name must not be empty");
    }
    if handler is None {
        raise ValueError("native tool requires a handler");
    }
    ent = RegisteredTool(
        name=name,
        description=description,
        parameters=parameters,
        origin="native",
        extension_id="",
        handler=handler,
    );
    reg.tools[name] = ent;
    return ent;
}


"""Register or replace a js-origin tool (schema only; invoke via bridge)."""
def register_js(
    reg: ToolRegistry,
    name: str,
    description: str,
    parameters: dict[str, any],
    extension_id: str,
) -> RegisteredTool {
    if not name {
        raise ValueError("tool name must not be empty");
    }
    if not extension_id {
        raise ValueError("js tool requires an extension_id");
    }
    ent = RegisteredTool(
        name=name,
        description=description,
        parameters=parameters,
        origin="js",
        extension_id=extension_id,
        handler=None,
    );
    reg.tools[name] = ent;
    return ent;
}


"""Seed the registry from an existing ToolSpec (native)."""
def register_native_spec(reg: ToolRegistry, spec: ToolSpec) -> RegisteredTool {
    if spec.handler is None {
        raise ValueError("native ToolSpec requires a handler");
    }
    return register_native(
        reg,
        spec.name,
        spec.description,
        spec.parameters,
        spec.handler,
    );
}


def get_tool(reg: ToolRegistry, name: str) -> RegisteredTool | None {
    if name in reg.tools {
        return reg.tools[name];
    }
    return None;
}


def unregister(reg: ToolRegistry, name: str) -> bool {
    if name in reg.tools {
        del reg.tools[name];
        return True;
    }
    return False;
}


"""Opaque-handle APIs for modules that keep ToolRegistry behind `any`.

These keep the concrete registry layout inside this module, so native callers
do not need the compiler to import the ToolRegistry field layout."""
def:pub has_tool_opaque(registry: any, name: str) -> bool {
    reg: ToolRegistry = registry as ToolRegistry;
    return get_tool(reg, name) is not None;
}


def:pub unregister_tool_opaque(registry: any, name: str) -> bool {
    reg: ToolRegistry = registry as ToolRegistry;
    return unregister(reg, name);
}


def:pub register_native_opaque(
    registry: any,
    name: str,
    description: str,
    parameters: dict[str, any],
    handler: Callable[[dict[str, any]], str],
) -> None {
    reg: ToolRegistry = registry as ToolRegistry;
    register_native(reg, name, description, parameters, handler);
}


def:pub registry_tool_names(registry: any) -> list[str] {
    reg: ToolRegistry = registry as ToolRegistry;
    names: list[str] = [];
    for (name, _tool) in reg.tools.items() {
        names.append(name);
    }
    return names;
}


def:pub register_native_handle(
    handle: int,
    name: str,
    description: str,
    parameters: dict[str, any],
    handler: Callable[[dict[str, any]], str],
) -> None {
    register_native(
        _registry_for_handle(handle), name, description, parameters, handler
    );
}


def:pub register_js_handle(
    handle: int,
    name: str,
    description: str,
    parameters: dict[str, any],
    extension_id: str,
) -> None {
    register_js(
        _registry_for_handle(handle), name, description, parameters, extension_id
    );
}


def:pub has_tool_handle(handle: int, name: str) -> bool {
    return get_tool(_registry_for_handle(handle), name) is not None;
}


def:pub unregister_tool_handle(handle: int, name: str) -> bool {
    return unregister(_registry_for_handle(handle), name);
}


def:pub registry_tool_names_handle(handle: int) -> list[str] {
    reg: ToolRegistry = _registry_for_handle(handle);
    names: list[str] = [];
    for (name, _tool) in reg.tools.items() {
        names.append(name);
    }
    return names;
}


def:pub registry_tool_specs_handle(handle: int) -> list[dict[str, any]] {
    reg: ToolRegistry = _registry_for_handle(handle);
    specs: list[dict[str, any]] = [];
    for (_name, tool) in reg.tools.items() {
        specs.append({
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters,
            "origin": tool.origin,
        });
    }
    return specs;
}


def:pub copy_registry_tools_handle(
    source_handle: int, target_handle: int, names: list[str]
) -> None {
    source: ToolRegistry = _registry_for_handle(source_handle);
    target: ToolRegistry = _registry_for_handle(target_handle);
    for name in names {
        tool: RegisteredTool | None = get_tool(source, name);
        if tool is not None {
            target.tools[name] = tool;
        }
    }
}


def:pub unregister_extension_handle(handle: int, extension_id: str) -> int {
    return unregister_extension(_registry_for_handle(handle), extension_id);
}


def:pub invoke_handle(
    handle: int, name: str, args: dict[str, any], bridge: any = None
) -> str {
    return invoke(_registry_for_handle(handle), name, args, bridge);
}


def:pub wrap_handler_handle(
    handle: int,
    name: str,
    after: Callable[[dict[str, any], str], None],
) -> bool {
    tool: RegisteredTool | None = get_tool(_registry_for_handle(handle), name);
    if tool is None or tool.handler is None {
        return False;
    }
    inner: Callable[[dict[str, any]], str] = tool.handler;
    def wrapped(args: dict[str, any]) -> str {
        result: str = str(inner(args));
        after(args, result);
        return result;
    }
    tool.handler = wrapped;
    return True;
}


"""Drop every tool contributed by one extension. Returns count removed."""
def unregister_extension(reg: ToolRegistry, extension_id: str) -> int {
    doomed: list[str] = [];
    for (name, ent) in reg.tools.items() {
        if ent.extension_id == extension_id {
            doomed.append(name);
        }
    }
    for name in doomed {
        del reg.tools[name];
    }
    return len(doomed);
}


"""ToolSpecs for react_loop. Js entries have handler=None (invoke via bridge)."""
def as_tool_specs(reg: ToolRegistry) -> list[ToolSpec] {
    out: list[ToolSpec] = [];
    for (_name, ent) in reg.tools.items() {
        out.append(
            make_tool_spec(
                name=ent.name,
                description=ent.description,
                parameters=ent.parameters,
                handler=ent.handler,
            )
        );
    }
    return out;
}


"""OpenAI-shape tool defs for the model (schema only, any origin)."""
def openai_tools(reg: ToolRegistry) -> list[dict[str, any]] {
    defs: list[dict[str, any]] = [];
    for (_name, ent) in reg.tools.items() {
        defs.append({
            "type": "function",
            "function": {
                "name": ent.name,
                "description": ent.description,
                "parameters": ent.parameters,
            },
        });
    }
    return defs;
}


"""Invoke a registered tool.

Native: call handler(args), where args is the decoded argument dictionary.
Js: require `bridge` with invoke_js_tool(bridge, name, args) -> str.
Unknown / missing handler / missing bridge -> ERROR string (loop-safe).
"""
def invoke(
    reg: ToolRegistry, name: str, args: dict[str, any], bridge: PluginBridge | None = None
) -> str {
    ent = get_tool(reg, name);
    if ent is None {
        return f"ERROR: unknown tool {name}";
    }
    if ent.origin == "native" {
        if ent.handler is None {
            return f"ERROR: native tool {name} has no handler";
        }
        try {
            return str(ent.handler(args));
        } except Exception as e {
            log_exception("registry.invoke", e, {"tool": name, "origin": "native"});
            return f"ERROR: {e}";
        }
    }
    if ent.origin == "js" {
        if bridge is None {
            return f"ERROR: js tool {name} requires a plugin bridge";
        }
        try {
            return str(invoke_tool(bridge, name, args));
        } except Exception as e {
            log_exception("registry.invoke", e, {"tool": name, "origin": "js"});
            return f"ERROR: {e}";
        }
    }
    return f"ERROR: unsupported tool origin {ent.origin}";
}
