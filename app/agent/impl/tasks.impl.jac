impl tasks_path(cwd: str) -> str {
    return os.path.join(cwd, ".jackal", TASKS_FILE);
}

impl generate_task_id -> str {
    return uuid.uuid4().hex[:8];
}

impl _now_iso -> str {
    return datetime.datetime.now(datetime.timezone.utc).isoformat();
}

impl _is_task(value: any) -> bool {
    return (
        isinstance(value, dict)
        and isinstance(value.get("id"), str)
        and isinstance(value.get("title"), str)
        and isinstance(value.get("status"), str)
        and isinstance(value.get("createdAt"), str)
        and isinstance(value.get("updatedAt"), str)
    );
}

impl load_tasks(cwd: str) -> list[dict[str, any]] {
    fh: any = None;
    try {
        fh = open(tasks_path(cwd), "r");
        parsed = json.load(fh);
    } except (OSError, ValueError) {
        return [];
    } finally {
        if fh is not None {
            fh.close();
        }
    }
    if not isinstance(parsed, list) {
        return [];
    }
    valid: list[dict[str, any]] = [];
    for item in parsed {
        if _is_task(item) {
            valid.append(item);
        }
    }
    return valid;
}

impl save_tasks(cwd: str, tasks: list[dict[str, any]]) -> bool {
    try {
        os.makedirs(os.path.join(cwd, ".jackal"), exist_ok=True);
    } except OSError {
        return False;
    }
    fh: any = None;
    try {
        fh = open(tasks_path(cwd), "w");
        fh.write(json_pretty(json.dumps(tasks)));
        fh.write("\n");
    } except OSError {
        return False;
    } finally {
        if fh is not None {
            fh.close();
        }
    }
    return True;
}

impl clear_tasks(cwd: str) -> bool {
    return save_tasks(cwd, []);
}

impl add_task(cwd: str, title: str, description: str = "") -> dict[str, any] {
    tasks = load_tasks(cwd);
    now = _now_iso();
    trimmed_desc = (description or "").strip();
    task: dict[str, any] = {
        "id": generate_task_id(),
        "title": title.strip(),
        "description": trimmed_desc or None,
        "status": "pending",
        "createdAt": now,
        "updatedAt": now,
    };
    tasks.append(task);
    save_tasks(cwd, tasks);
    return task;
}

impl remove_task_by_index(cwd: str, index: int) -> dict[str, any] | None {
    tasks = load_tasks(cwd);
    if index < 0 or index >= len(tasks) {
        return None;
    }
    removed = tasks.pop(index);
    save_tasks(cwd, tasks);
    return removed;
}

impl remove_task_by_id(cwd: str, task_id: str) -> dict[str, any] | None {
    tasks = load_tasks(cwd);
    idx: int = -1;
    pos: int = 0;
    while pos < len(tasks) {
        if str(tasks[pos]["id"]) == task_id {
            idx = pos;
            break;
        }
        pos += 1;
    }
    if idx < 0 {
        return None;
    }
    removed = tasks.pop(idx);
    save_tasks(cwd, tasks);
    return removed;
}

impl update_tasks(cwd: str, updates: list[dict[str, any]]) -> list[dict[str, any]] {
    tasks = load_tasks(cwd);
    now = _now_iso();
    for update in updates {
        if not isinstance(update, dict) {
            continue;
        }
        idx: int = -1;
        pos: int = 0;
        while pos < len(tasks) {
            if str(tasks[pos]["id"]) == str(update.get("id")) {
                idx = pos;
                break;
            }
            pos += 1;
        }
        if idx < 0 {
            continue;
        }
        task: dict[str, any] = dict(tasks[idx]);
        if "status" in update {
            task["status"] = update["status"];
            if update["status"] == "completed" {
                task["completedAt"] = now;
            } else {
                task["completedAt"] = None;
            }
        }
        if "title" in update {
            task["title"] = update["title"];
        }
        if "description" in update {
            task["description"] = update["description"];
        }
        task["updatedAt"] = now;
        tasks[idx] = task;
    }
    save_tasks(cwd, tasks);
    return tasks;
}

impl task_counts(tasks: list[dict[str, any]]) -> dict[str, int] {
    pending: int = 0;
    in_progress: int = 0;
    completed: int = 0;
    for t in tasks {
        status = str(t.get("status", ""));
        if status == "pending" {
            pending += 1;
        } elif status == "in_progress" {
            in_progress += 1;
        } elif status == "completed" {
            completed += 1;
        }
    }
    return {"pending": pending, "in_progress": in_progress, "completed": completed};
}

impl format_task_line(task: dict[str, any]) -> str {
    icon: str = "○";
    status = str(task.get("status", ""));
    if status == "completed" {
        icon = "✓";
    } elif status == "in_progress" {
        icon = "◐";
    }
    desc = task.get("description");
    suffix: str = "";
    if isinstance(desc, str) and desc {
        suffix = " — " + desc;
    }
    return icon + " [" + str(task["id"]) + "] " + str(task["title"]) + suffix;
}

impl format_tasks_list(tasks: list[dict[str, any]], title: str = "Tasks") -> str {
    if not tasks {
        return _NO_TASKS_LINE;
    }
    counts = task_counts(tasks);
    header = (
        title
        + " ("
        + str(counts["pending"])
        + " pending"
        + ", "
        + str(counts["in_progress"])
        + " in progress"
        + ", "
        + str(counts["completed"])
        + " completed)"
    );
    lines: list[str] = [];
    idx: int = 0;
    while idx < len(tasks) {
        lines.append(str(idx + 1) + ". " + format_task_line(tasks[idx]));
        idx += 1;
    }
    return header + "\n" + ("─" * 50) + "\n" + "\n".join(lines);
}
