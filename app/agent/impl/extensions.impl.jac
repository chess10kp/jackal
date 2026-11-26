impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_dirname(p: str) -> str {
    return str(os.path.dirname(p));
}

impl decl_from_dict(raw: dict[str, any]) -> ExtensionDecl {
    req: list[str] = [];
    raw_req: any = raw.get("requires", []);
    if isinstance(raw_req, list) {
        req = [str(x) for x in raw_req];
    }
    runtime = str(raw.get("runtime", "node") or "node");
    activation = str(raw.get("activation", "") or "");
    if not activation {
        if runtime == "native" {
            activation = "native";
        } else {
            activation = "sidecar";
        }
    }
    return ExtensionDecl(
        id=str(raw.get("id", "")),
        path=str(raw.get("path", "")),
        runtime=runtime,
        activation=activation,
        requires=req,
    );
}

impl decls_from_json(data: any) -> list[ExtensionDecl] {
    rows: list[any] = [];
    if isinstance(data, list) {
        rows = data;
    } elif isinstance(data, dict) {
        maybe: any = data.get("extensions", []);
        if isinstance(maybe, list) {
            rows = maybe;
        }
    }
    out: list[ExtensionDecl] = [];
    for row in rows {
        if isinstance(row, dict) {
            d = decl_from_dict(row);
            if d.id and d.path {
                out.append(d);
            }
        }
    }
    return out;
}

impl load_extension_decls(cwd: str = "") -> list[ExtensionDecl] {
    start = cwd or os.getcwd();
    cur = _path_abspath(start);
    while True {
        ext_path = os.path.join(cur, ".jackal", "extensions.json");
        if os.path.isfile(ext_path) {
            try {
                with open(ext_path, "r") as fh {
                    return decls_from_json(json.load(fh));
                }
            } except (OSError, ValueError) {}
        }
        jackal_path = os.path.join(cur, ".jackal");
        if os.path.isfile(jackal_path) {
            try {
                with open(jackal_path, "r") as fh {
                    data = json.load(fh);
                }
                if isinstance(data, dict) and "extensions" in data {
                    return decls_from_json(data);
                }
            } except (OSError, ValueError) {}
        }
        parent = _path_dirname(cur);
        if parent == cur {
            break;
        }
        cur = parent;
    }
    return [];
}

impl node_sidecar_decls(decls: list[ExtensionDecl]) -> list[ExtensionDecl] {
    out: list[ExtensionDecl] = [];
    for d in decls {
        if d.runtime != "node" {
            continue;
        }
        if d.activation == "lazy" {
            continue;
        }
        out.append(d);
    }
    return out;
}

impl extensions_label(status: ExtensionStatus) -> str {
    if status.total <= 0 {
        return "extensions: idle";
    }
    if status.phase == "ready" and status.ready {
        return f"extensions: ready {status.loaded}/{status.total}";
    }
    if status.phase == "degraded" {
        return f"extensions: degraded {status.loaded}/{status.total}";
    }
    if status.phase == "dead" {
        return f"extensions: dead {status.loaded}/{status.total}";
    }
    return f"extensions: loading {status.loaded}/{status.total}";
}

impl resolve_decl_path(decl: ExtensionDecl, base_cwd: str) -> str {
    p = decl.path;
    if os.path.isabs(p) {
        return p;
    }
    return _path_abspath(os.path.join(base_cwd, p));
}
