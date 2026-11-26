impl list_chain_files(dir_path: str) -> list[str] {
    found: list[str] = [];
    if not os.path.isdir(dir_path) {
        return found;
    }
    try {
        names = sorted(os.listdir(dir_path));
    } except OSError {
        return found;
    }
    dirs: list[str] = [];
    files: list[str] = [];
    for name in names {
        full = os.path.join(dir_path, name);
        if os.path.isdir(full) {
            dirs.append(full);
        } elif os.path.isfile(full) and name.endswith(".chain.md") {
            files.append(full);
        }
    }
    found.extend(files);
    for sub in dirs {
        found.extend(list_chain_files(sub));
    }
    return found;
}

impl parse_step_body(agent: str, section_body: str) -> dict[str, any] {
    lines = section_body.split("\n");
    blank_index = -1;
    idx = 0;
    for line in lines {
        if line.strip() == "" {
            blank_index = idx;
            break;
        }
        idx += 1;
    }
    if blank_index == -1 {
        config_lines = lines;
        task = "";
    } else {
        config_lines = lines[:blank_index];
        task = "\n".join(lines[blank_index + 1:]).strip();
    }

    step: dict[str, any] = {"agent": agent, "task": task};
    for line in config_lines {
        found = re.match(r"^([\w-]+):\s*(.*)$", line);
        if not found {
            continue;
        }
        key = str(found.group(1)).strip().lower();
        raw_value = str(found.group(2)).strip();
        if key == "output" and raw_value {
            step["output"] = raw_value;
            continue;
        }
        if key == "reads" and raw_value {
            reads: list[str] = [];
            for p in raw_value.split(",") {
                piece = p.strip();
                if piece {
                    reads.append(piece);
                }
            }
            step["reads"] = reads;
            continue;
        }
        if key == "model" and raw_value {
            step["model"] = raw_value;
        }
    }
    return step;
}

impl parse_chain_markdown(content: str, source: str, file_path: str) -> dict[str, any] {
    (fm, body) = parse_frontmatter(content);
    raw_name = frontmatter_string(fm.get("name"));
    name = (raw_name or "").strip();
    raw_desc = frontmatter_string(fm.get("description"));
    description = (raw_desc or "").strip();

    if not name or not description {
        raise ValueError("Chain frontmatter must include name and description (" + file_path + ")");
    }
    steps: list[dict[str, any]] = [];
    current_agent = "";
    section_lines: list[str] = [];
    for line in body.split("\n") {
        heading = re.match(r"^##\s+(.+?)\s*$", line);
        if heading is not None {
            if current_agent {
                section_body = "\n".join(section_lines).rstrip();
                steps.append(parse_step_body(current_agent, section_body));
            }
            current_agent = str(heading.group(1)).strip();
            section_lines = [];
        } elif current_agent {
            section_lines.append(line);
        }
    }
    if current_agent {
        tail_body = "\n".join(section_lines).rstrip();
        steps.append(parse_step_body(current_agent, tail_body));
    }

    if not steps {
        raise ValueError("Chain '" + name + "' has no ## steps (" + file_path + ")");
    }

    return {
        "name": name,
        "description": description,
        "steps": steps,
        "source": source,
        "filePath": file_path,
    };
}

impl load_chains_from_dir(dir_path: str, source: str) -> list[dict[str, any]] {
    chains: list[dict[str, any]] = [];
    for file_path in list_chain_files(dir_path) {
        try {
            fh = open(file_path, encoding="utf-8");
            try {
                content = fh.read();
            } finally {
                fh.close();
            }
            chains.append(parse_chain_markdown(content, source, file_path));
        } except Exception {}
    }
    return chains;
}

impl discover_chain_dirs(cwd: str, agent_dir: str = "") -> dict[str, str] {
    base_root = agent_dir or resolve_jackal_root();
    return {
        "packageDir": os.path.join(base_root, "chains"),
        "projectDir": os.path.join(_abs_path(cwd), "chains"),
    };
}

impl load_chains(cwd: str, agent_dir: str = "") -> dict[str, dict[str, any]] {
    dirs = discover_chain_dirs(cwd, agent_dir);
    merged: dict[str, dict[str, any]] = {};
    for chain in load_chains_from_dir(str(dirs["packageDir"]), "package") {
        merged[str(chain["name"])] = chain;
    }
    for chain in load_chains_from_dir(str(dirs["projectDir"]), "project") {
        merged[str(chain["name"])] = chain;
    }
    return merged;
}

impl _chain_sort_key(chain: dict[str, any]) -> str {
    return str(chain.get("name", ""));
}

impl list_chains(cwd: str, agent_dir: str = "") -> list[dict[str, any]] {
    chains: list[dict[str, any]] = list(load_chains(cwd, agent_dir).values());
    return sorted(chains, key=_chain_sort_key);
}

impl get_chain(cwd: str, name: str, agent_dir: str = "") -> dict[str, any] | None {
    return load_chains(cwd, agent_dir).get(name.strip());
}

impl format_chain_catalog(cwd: str, agent_dir: str = "") -> str {
    chains = list_chains(cwd, agent_dir);
    if not chains {
        return "No chains found.";
    }
    lines: list[str] = ["Available chains:", ""];
    for chain in chains {
        agents_seq: list[str] = [];
        steps: any = chain["steps"];
        for step in steps {
            step_dict: dict[str, any] = step;
            agents_seq.append(str(step_dict.get("agent", "")));
        }
        lines.append(
            "- "
                + str(chain["name"])
                + " ("
                + str(chain["source"])
                + ") — "
                + str(chain["description"]),
        );
        lines.append("  steps: " + " → ".join(agents_seq));
    }
    return "\n".join(lines);
}

impl chain_dirs_exist(cwd: str, agent_dir: str = "") -> bool {
    dirs = discover_chain_dirs(cwd, agent_dir);
    return os.path.isdir(str(dirs["packageDir"])) or os.path.isdir(str(dirs["projectDir"]));
}
