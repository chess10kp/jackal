impl _escape_xml(s: str) -> str {
    out = s.replace("&", "&amp;");
    out = out.replace("<", "&lt;");
    out = out.replace(">", "&gt;");
    out = out.replace('"', "&quot;");
    out = out.replace("'", "&apos;");
    return out;
}

impl format_skills_for_prompt(skills: list[dict[str, any]]) -> str {
    visible: list[dict[str, any]] = [];
    for s in skills {
        if not s.get("disableModelInvocation", False) {
            visible.append(s);
        }
    }
    if not visible {
        return "";
    }
    lines: list[str] = [];
    lines.append("\n\nThe following skills provide specialized instructions for specific tasks.");
    lines.append("Use the read tool to load a skill's file when the task matches its description.");
    lines.append(
        "When a skill file references a relative path, resolve it against the skill directory "
            + "(parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.",
    );
    lines.append("");
    lines.append("<available_skills>");
    for s in visible {
        lines.append("  <skill>");
        lines.append("    <name>" + _escape_xml(str(s.get("name", ""))) + "</name>");
        lines.append(
            "    <description>" + _escape_xml(str(s.get("description", ""))) + "</description>"
        );
        lines.append("    <location>" + _escape_xml(str(s.get("filePath", ""))) + "</location>");
        lines.append("  </skill>");
    }
    lines.append("</available_skills>");
    return "\n".join(lines);
}

impl append_skills_to_prompt(system_prompt: str, skills: list[dict[str, any]]) -> str {
    catalog = format_skills_for_prompt(skills);
    if catalog {
        return system_prompt + catalog;
    }
    return system_prompt;
}

impl expand_skill_command(text: str, skills: list[dict[str, any]]) -> str {
    if not text.startswith("/skill:") {
        return text;
    }
    space = text.find(" ");
    if space != -1 {
        skill_name = text[7:space];
        args = text[space + 1:].strip();
    } else {
        skill_name = text[7:];
        args = "";
    }

    found: dict[str, any] | None = None;
    for s in skills {
        if str(s.get("name", "")) == skill_name {
            found = s;
            break;
        }
    }
    if found is None {
        return text;
    }
    skill_path = str(found.get("filePath", ""));
    skill_base = str(found.get("baseDir", ""));
    try {
        fh = open(skill_path, encoding="utf-8");
        try {
            raw = fh.read();
        } finally {
            fh.close();
        }
        (_fm, body) = parse_frontmatter(raw);
        block = (
            '<skill name="'
            + skill_name
            + '" location="'
            + skill_path
            + '">\n'
            + "References are relative to "
            + skill_base
            + ".\n\n"
            + body.strip()
            + "\n</skill>"
        );
        if args {
            return block + "\n\n" + args;
        }
        return block;
    } except Exception {
        return text;
    }
}

impl load_skill_by_dir(dir_name: str, package_root: str = "") -> str {
    pkg_base = package_root or _resolve_package_root();
    fpath = os.path.join(pkg_base, "pi", "skills", dir_name, "SKILL.md");
    if not os.path.isfile(fpath) {
        return "";
    }
    try {
        fh = open(fpath, encoding="utf-8");
        try {
            raw = fh.read();
        } finally {
            fh.close();
        }
        (_fm, body) = parse_frontmatter(raw);
        return body.strip();
    } except Exception {
        return "";
    }
}

impl skill_read_allowlist(skills: list[dict[str, any]]) -> dict[str, list[str]] {
    files: list[str] = [];
    roots: list[str] = [];
    for s in skills {
        files.append(_abs_path(str(s.get("filePath", ""))));
        roots.append(_abs_path(str(s.get("baseDir", ""))) + os.sep);
    }
    return {"files": files, "roots": roots};
}
