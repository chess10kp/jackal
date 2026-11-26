impl create_registry -> ToolRegistry {
    return ToolRegistry();
}

impl register_native(
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

impl register_js(
    reg: ToolRegistry, name: str, description: str, parameters: dict[str, any], extension_id: str
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

impl register_native_spec(reg: ToolRegistry, spec: ToolSpec) -> RegisteredTool {
    if spec.handler is None {
        raise ValueError("native ToolSpec requires a handler");
    }
    return register_native(reg, spec.name, spec.description, spec.parameters, spec.handler);
}

impl get_tool(reg: ToolRegistry, name: str) -> RegisteredTool | None {
    if name in reg.tools {
        return reg.tools[name];
    }
    return None;
}

impl unregister(reg: ToolRegistry, name: str) -> bool {
    if name in reg.tools {
        del reg.tools[name];
        return True;
    }
    return False;
}

impl unregister_extension(reg: ToolRegistry, extension_id: str) -> int {
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

impl as_tool_specs(reg: ToolRegistry) -> list[ToolSpec] {
    out: list[ToolSpec] = [];
    for (_name, ent) in reg.tools.items() {
        out.append(
            make_tool_spec(
                name=ent.name,
                description=ent.description,
                parameters=ent.parameters,
                handler=ent.handler,
            ),
        );
    }
    return out;
}

impl openai_tools(reg: ToolRegistry) -> list[dict[str, any]] {
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

impl invoke(reg: ToolRegistry, name: str, args: dict[str, any], bridge: any = None) -> str {
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
            return str(bridge.invoke_js_tool(name, args));
        } except Exception as e {
            log_exception("registry.invoke", e, {"tool": name, "origin": "js"});
            return f"ERROR: {e}";
        }
    }
    return f"ERROR: unsupported tool origin {ent.origin}";
}
