def _make_tmp -> str {
    return tempfile.mkdtemp(prefix="jackal-skills-test-");
}

def _cleanup(tmp: str) {
    shutil.rmtree(tmp, ignore_errors=True);
}

def _write_text(path: str, text: str) {
    os.makedirs(_dir_name(path), exist_ok=True);
    fh = open(path, "w");
    try {
        fh.write(text);
    } finally {
        fh.close();
    }
}

def _write_bytes_as_latin1(path: str, text: str) {
    os.makedirs(_dir_name(path), exist_ok=True);
    fh = open(path, "w", encoding="latin-1");
    try {
        fh.write(text);
    } finally {
        fh.close();
    }
}

def _write_skill(
    dir_path: str, name: str, description: str, extra_fm: str = "", body: str = "Skill body text."
) -> str {
    fm = "name: " + name + "\ndescription: " + description;
    if extra_fm {
        fm += "\n" + extra_fm;
    }
    path = os.path.join(dir_path, "SKILL.md");
    _write_text(path, "---\n" + fm + "\n---\n\n" + body + "\n");
    return path;
}

def _names(result: dict[str, list[dict[str, any]]]) -> list[str] {
    out: list[str] = [];
    items: list[dict[str, any]] = result["skills"];
    for item in items {
        rec: dict[str, any] = item;
        out.append(str(rec["name"]));
    }
    return out;
}

def _diag_types(result: dict[str, list[dict[str, any]]], kind: str) -> list[dict[str, any]] {
    found: list[dict[str, any]] = [];
    diags: list[dict[str, any]] = result["diagnostics"];
    for d in diags {
        diag: dict[str, any] = d;
        if str(diag["type"]) == kind {
            found.append(diag);
        }
    }
    return found;
}

test "discovery walk claims SKILL.md branches and skips hidden vendor dirs" {
    tmp = _make_tmp();
    try {
        skills_root = os.path.join(tmp, "skills");
        _write_skill(os.path.join(skills_root, "alpha"), "alpha", "Alpha skill.");
        _write_skill(os.path.join(skills_root, "beta", "tools"), "beta", "Beta tooling.");
        _write_skill(os.path.join(skills_root, ".hidden"), "secret", "Should not load.");
        _write_skill(os.path.join(skills_root, "node_modules", "dep"), "dep", "Nope.");
        _write_text(os.path.join(skills_root, "gamma", ".gitignore"), "SKILL.md\n");
        _write_skill(os.path.join(skills_root, "gamma"), "gamma", "Ignored by rule.");

        result: dict[str, list[dict[str, any]]] = load_skills_from_dir(skills_root, "project");
        assert sorted(_names(result)) == ["alpha", "beta"];
        assert len(_diag_types(result, "collision")) == 0;

        items: list[dict[str, any]] = result["skills"];
        for item in items {
            s: dict[str, any] = item;
            assert _base_name(str(s["filePath"])) == "SKILL.md";
            assert str(s["baseDir"]) == _dir_name(str(s["filePath"]));
            assert str(s["source"]) == "project";
            assert s["disableModelInvocation"] is False;
        }
        plain_root = os.path.join(tmp, "plain");
        os.makedirs(plain_root, exist_ok=True);
        _write_skill(os.path.join(plain_root, "nested"), "nested-skill", "Nested.");
        _write_text(
            os.path.join(plain_root, "loose.md"),
            "---\nname: loose-note\ndescription: A root level note.\n---\n\nNote body.\n",
        );
        loose: dict[str, list[dict[str, any]]] = load_skills_from_dir(plain_root, "builtin");
        assert sorted(_names(loose)) == ["loose-note", "nested-skill"];
        loose_items: list[dict[str, any]] = loose["skills"];
        first: dict[str, any] = loose_items[0];
        assert str(first["source"]) == "builtin";
        absent = load_skills_from_dir(os.path.join(tmp, "nope"), "user");
        assert absent["skills"] == [] and absent["diagnostics"] == [];
    } finally {
        _cleanup(tmp);
    }
}

test "frontmatter parser handles scalars, quoting, lists, and absence" {
    doc = ("---\n"
        "name: demo-skill\n"
        'quoted: "hello world"\n'
        "apostrophe: 'single quoted'\n"
        "tags: [alpha, beta, gamma]\n"
        "empty_list: []\n"
        "steps:\n"
        "  - first\n"
        "  - second\n"
        "---\n\n"
        "Body line one.\n\nBody line two.\n");
    parsed = parse_frontmatter(doc);
    fm: dict[str, any] = parsed[0];
    body: str = parsed[1];
    assert str(fm.get("name")) == "demo-skill";
    assert str(fm.get("quoted")) == "hello world";
    assert str(fm.get("apostrophe")) == "single quoted";
    tags: any = fm.get("tags");
    assert tags == ["alpha", "beta", "gamma"];
    assert fm.get("empty_list") == [];
    steps: any = fm.get("steps");
    assert steps == ["first", "second"];
    assert body == "Body line one.\n\nBody line two.";
    parsed2 = parse_frontmatter("just prose, nothing else");
    assert parsed2[0] == {} and parsed2[1] == "just prose, nothing else";
    parsed3 = parse_frontmatter("---\nname: never-closed");
    assert parsed3[0] == {} and "never-closed" in parsed3[1];
    parsed4 = parse_frontmatter("---\r\nname: crlf\r\ndescription: d\r\n---\r\n\r\nB\r\n");
    fm4: dict[str, any] = parsed4[0];
    assert str(fm4.get("name")) == "crlf";
    assert parsed4[1] == "B";

    assert frontmatter_string(None) is None;
    assert frontmatter_string("plain") == "plain";
    assert frontmatter_string(["a", "b"]) == "a, b";
}

test "malformed SKILL.md files produce warnings without crashing" {
    tmp = _make_tmp();
    try {
        tree_base = os.path.join(tmp, "skills");
        os.makedirs(tree_base, exist_ok=True);
        _write_text(
            os.path.join(tree_base, "nodesc", "SKILL.md"),
            "---\nname: nodesc\n---\n\nNo description here.\n",
        );
        _write_skill(os.path.join(tree_base, "badname"), "Bad Name!", "Still usable.");
        long_name = "a" * 80;
        _write_skill(os.path.join(tree_base, "toolong"), long_name, "Too long name.");
        _write_text(os.path.join(tree_base, "emptyf", "SKILL.md"), "");
        _write_bytes_as_latin1(
            os.path.join(tree_base, "binary", "SKILL.md"), "\xff\xfe\x00not utf8"
        );
        _write_text(
            os.path.join(tree_base, "garbled", "SKILL.md"),
            "---\nname [broken: ===\nno closing delimiter ever",
        );
        _write_skill(os.path.join(tree_base, "goodone"), "goodone", "Fine.");

        result: dict[str, list[dict[str, any]]] = load_skills_from_dir(tree_base, "path");
        names = _names(result);
        assert "nodesc" not in names;
        assert "emptyf" not in names;
        assert "Bad Name!" in names;
        assert long_name in names;

        warnings = _diag_types(result, "warning");
        messages: list[str] = [];
        for w in warnings {
            wd: dict[str, any] = w;
            messages.append(str(wd["message"]));
        }
        assert any("description is required" in m for m in messages);
        assert any("invalid characters" in m for m in messages);
        assert any("exceeds 64 characters" in m for m in messages);
        assert "goodone" in names;
        for w in warnings {
            wd2: dict[str, any] = w;
            wp: any = wd2["path"];
            assert str(wp).endswith(".md");
        }
        merged = load_jackal_skills(cwd=tmp, package_root=tmp, agent_dir=os.path.join(tmp, "home"));
        merged_skills: list[dict[str, any]] = merged["skills"];
        assert isinstance(merged_skills, list);
    } finally {
        _cleanup(tmp);
    }
}

test "load_jackal_skills merges roots with precedence, sorting, collisions" {
    tmp = _make_tmp();
    try {
        pkg = os.path.join(tmp, "pkg");
        _write_skill(os.path.join(pkg, "pi", "skills", "zeta"), "zeta", "Built-in zeta.");
        _write_skill(os.path.join(pkg, "pi", "skills", "alpha"), "alpha", "Built-in alpha.");
        dupe_builtin = _write_skill(
            os.path.join(pkg, "pi", "skills", "dupe"), "dupe", "Builtin dupe."
        );

        home = os.path.join(tmp, "home");
        _write_skill(os.path.join(home, "skills", "beta"), "beta", "User beta.");
        dupe_user = _write_skill(
            os.path.join(home, "skills", "dupe"),
            "dupe",
            "User dupe wins.",
            extra_fm="disable-model-invocation: true",
        );

        proj = os.path.join(tmp, "proj");
        _write_skill(os.path.join(proj, ".jackal", "skills", "gamma"), "gamma", "Project gamma.");

        result: dict[str, list[dict[str, any]]] = load_jackal_skills(
            cwd=proj, package_root=pkg, agent_dir=home
        );
        assert _names(result) == ["alpha", "beta", "dupe", "gamma", "zeta"];

        by_name: dict[str, dict[str, any]] = {};
        items: list[dict[str, any]] = result["skills"];
        for item in items {
            s: dict[str, any] = item;
            by_name[str(s["name"])] = s;
        }
        winner_zeta: dict[str, any] = by_name["zeta"];
        assert str(winner_zeta["source"]) == "builtin";
        winner_beta: dict[str, any] = by_name["beta"];
        assert str(winner_beta["source"]) == "user";
        winner_gamma: dict[str, any] = by_name["gamma"];
        assert str(winner_gamma["source"]) == "project";
        winner_dupe: dict[str, any] = by_name["dupe"];
        assert str(winner_dupe["source"]) == "user";
        assert str(winner_dupe["description"]) == "User dupe wins.";
        assert winner_dupe["disableModelInvocation"] is True;
        collisions = _diag_types(result, "collision");
        assert len(collisions) == 1;
        col0: dict[str, any] = collisions[0];
        col: any = col0["collision"];
        assert str(col["name"]) == "dupe";
        assert str(col["winnerPath"]) == dupe_user;
        assert str(col["loserPath"]) == dupe_builtin;
        only_paths: dict[str, list[dict[str, any]]] = load_jackal_skills(
            cwd=proj,
            package_root=pkg,
            agent_dir=home,
            include_defaults=False,
            skill_paths=[os.path.join(pkg, "pi", "skills", "alpha")],
        );
        assert _names(only_paths) == ["alpha"];
        nested_cwd = os.path.join(proj, "deep", "deeper");
        os.makedirs(nested_cwd, exist_ok=True);
        walked_up: dict[str, list[dict[str, any]]] = load_jackal_skills(
            cwd=nested_cwd, package_root=pkg, agent_dir=home
        );
        assert "gamma" in _names(walked_up);
    } finally {
        _cleanup(tmp);
    }
}

test "explicit skill_paths resolve relative, home, and error cases" {
    tmp = _make_tmp();
    try {
        proj = os.path.join(tmp, "proj");
        target = _write_skill(os.path.join(proj, "local"), "local-one", "Local dir.");
        single_md = _write_text(
            os.path.join(proj, "standalone.md"),
            "---\nname: standalone\ndescription: One file skill.\n---\n\nBody.\n",
        );
        _write_text(os.path.join(proj, "notmd.txt"), "plain text");
        rel: dict[str, list[dict[str, any]]] = load_jackal_skills(
            cwd=proj, include_defaults=False, skill_paths=["local"]
        );
        assert _names(rel) == ["local-one"];
        rel_items: list[dict[str, any]] = rel["skills"];
        rel0: dict[str, any] = rel_items[0];
        assert str(rel0["filePath"]) == target;
        solo: dict[str, list[dict[str, any]]] = load_jackal_skills(
            cwd=proj, include_defaults=False, skill_paths=["standalone.md", str(single_md)]
        );
        assert _names(solo) == ["standalone"];
        errs = load_jackal_skills(
            cwd=proj, include_defaults=False, skill_paths=["missing-dir", "notmd.txt"]
        );
        assert errs["skills"] == [];
        msgs: list[str] = [];
        err_diags: list[dict[str, any]] = errs["diagnostics"];
        for d in err_diags {
            ed: dict[str, any] = d;
            msgs.append(str(ed["message"]));
        }
        assert any("does not exist" in m for m in msgs);
        assert any("not a markdown file" in m for m in msgs);
        home = os.path.join(tmp, "home");
        _write_skill(os.path.join(home, "skills", "homed"), "homed", "From home.");
        tagged = load_jackal_skills(
            cwd=proj,
            package_root=proj,
            agent_dir=home,
            include_defaults=False,
            skill_paths=[os.path.join(home, "skills", "homed")],
        );
        tagged_items: list[dict[str, any]] = tagged["skills"];
        tag0: dict[str, any] = tagged_items[0];
        assert str(tag0["source"]) == "user";
        old_home = os.environ.get("HOME");
        os.environ["HOME"] = home;
        try {
            tilded: dict[str, list[dict[str, any]]] = load_jackal_skills(
                cwd=proj, include_defaults=False, skill_paths=["~/skills/homed"]
            );
            assert _names(tilded) == ["homed"];
        } finally {
            if old_home is None {
                os.environ.pop("HOME");
            } else {
                os.environ["HOME"] = old_home;
            }
        }
    } finally {
        _cleanup(tmp);
    }
}

test "format_skills_for_prompt escapes xml and honors the disable flag" {
    tmp = _make_tmp();
    try {
        visible: dict[str, any] = {
            "name": "escaper",
            "description": "Handles a<b & c>d \"quotes\" and 'apos'.",
            "filePath": os.path.join(tmp, "escaper", "SKILL.md"),
            "baseDir": os.path.join(tmp, "escaper"),
            "source": "builtin",
            "disableModelInvocation": False,
        };
        hidden: dict[str, any] = {
            "name": "hidden-one",
            "description": "Never shown.",
            "filePath": os.path.join(tmp, "hidden-one", "SKILL.md"),
            "baseDir": os.path.join(tmp, "hidden-one"),
            "source": "builtin",
            "disableModelInvocation": True,
        };
        block = format_skills_for_prompt([visible, hidden]);
        assert "<available_skills>" in block and "</available_skills>" in block;
        assert "<name>escaper</name>" in block;
        assert "&lt;b &amp; c&gt;d &quot;quotes&quot; and &apos;apos&apos;" in block;
        assert "hidden-one" not in block;
        assert "Use the read tool to load a skill's file" in block;
        assert "resolve it against the skill directory" in block;

        assert format_skills_for_prompt([]) == "";
        assert format_skills_for_prompt([hidden]) == "";

        base = "SYSTEM PROMPT";
        assert append_skills_to_prompt(base, [visible]) == base + block;
        assert append_skills_to_prompt(base, []) == base;
    } finally {
        _cleanup(tmp);
    }
}

test "expand_skill_command inlines the referenced skill body" {
    tmp = _make_tmp();
    try {
        dir_path = os.path.join(tmp, "demo");
        path = _write_skill(dir_path, "demo", "Demo skill.", body="Step 1. Step 2.");
        skill: dict[str, any] = {
            "name": "demo",
            "description": "Demo skill.",
            "filePath": path,
            "baseDir": dir_path,
            "source": "builtin",
            "disableModelInvocation": False,
        };
        expanded = expand_skill_command("/skill:demo please run it", [skill]);
        assert '<skill name="demo" location="' + path + '">' in expanded;
        assert "References are relative to " + dir_path + "." in expanded;
        assert "Step 1. Step 2." in expanded;
        assert "</skill>\n\nplease run it" in expanded;
        bare = expand_skill_command("/skill:demo", [skill]);
        assert bare.endswith("</skill>");
        assert expand_skill_command("/skill:nope hi", [skill]) == "/skill:nope hi";
        assert expand_skill_command("just chat", [skill]) == "just chat";
        broken: dict[str, any] = dict(skill);
        broken["filePath"] = os.path.join(tmp, "gone", "SKILL.md");
        assert expand_skill_command("/skill:demo x", [broken]) == "/skill:demo x";
    } finally {
        _cleanup(tmp);
    }
}

test "load_skill_by_dir returns stripped bodies and empty on misses" {
    tmp = _make_tmp();
    try {
        _write_skill(
            os.path.join(tmp, "pi", "skills", "realone"),
            "realone",
            "Real one.",
            body="Real body here.",
        );
        assert load_skill_by_dir("realone", package_root=tmp) == "Real body here.";
        assert load_skill_by_dir("missing", package_root=tmp) == "";
        _write_bytes_as_latin1(
            os.path.join(tmp, "pi", "skills", "corrupt", "SKILL.md"), "\xff\xfe\x00\xff"
        );
        assert load_skill_by_dir("corrupt", package_root=tmp) == "";
    } finally {
        _cleanup(tmp);
    }
}

test "skill_read_allowlist yields absolute files and rooted base dirs" {
    tmp = _make_tmp();
    try {
        p1 = _write_skill(os.path.join(tmp, "one"), "one", "One.");
        p2 = _write_skill(os.path.join(tmp, "two"), "two", "Two.");
        skills: list[dict[str, any]] = [
            {
                "name": "one",
                "description": "One.",
                "filePath": p1,
                "baseDir": _dir_name(p1),
                "source": "builtin",
                "disableModelInvocation": False,
            },
            {
                "name": "two",
                "description": "Two.",
                "filePath": p2,
                "baseDir": _dir_name(p2),
                "source": "user",
                "disableModelInvocation": True,
            },
        ];
        allow = skill_read_allowlist(skills);
        files: list[str] = allow["files"];
        roots: list[str] = allow["roots"];
        assert files == [p1, p2];
        assert roots == [_dir_name(p1) + os.sep, _dir_name(p2) + os.sep];
    } finally {
        _cleanup(tmp);
    }
}

test "real jackal catalog under pi/skills parses read-only" {
    probe = os.getcwd();
    repo = "";
    for _hop in range(8) {
        if os.path.isdir(os.path.join(probe, "pi", "skills")) {
            repo = probe;
            break;
        }
        parent = _dir_name(probe);
        if parent == probe {
            break;
        }
        probe = parent;
    }
    if not repo {
        return;
    }
    tmp = _make_tmp();
    try {
        result = load_jackal_skills(
            cwd=tmp, package_root=repo, agent_dir=os.path.join(tmp, "home")
        );
        items: list[dict[str, any]] = result["skills"];
        assert len(items) >= 20;
        prev = "";
        for item in items {
            s: dict[str, any] = item;
            name = str(s["name"]);
            desc = str(s["description"]);
            assert name != "";
            assert desc != "";
            assert os.path.isfile(str(s["filePath"]));
            assert str(s["filePath"]).startswith(os.path.join(repo, "pi", "skills"));
            assert str(s["source"]) == "builtin";
            if prev {
                assert prev <= name;
            }
            prev = name;
        }
    } finally {
        _cleanup(tmp);
    }
}
