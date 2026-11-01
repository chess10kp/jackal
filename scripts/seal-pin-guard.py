#!/usr/bin/env python3
"""Static guard for hard native-placement pins (see app/jac.toml).

Why this exists
---------------
`jac build` seals each native unit and refuses to silently demote a module
that is pinned `native` in `[placement.pins]`. That seal is expensive (it
needs a built native kernel), so CI cannot run it on every push yet.

A large class of seal failures is decidable from the source alone:

  * a hard-pinned-native module whose *own* imports reach a server-pinned
    module that it calls with a non-C-ABI signature is `E5093` at seal time;
  * the same is true for the module's `.impl.jac` / `.test.jac` annexes,
    because `NativeUnitRegistry._module_files_and_imports` folds annexes
    into the module's unit (compiler/driver/impl/nativecache.impl.jac).
    A pinned-native module whose annex only needs the server to test it
    still fails the whole unit.

This script reports those crossings without a compiler, so a regression is
caught in the cheap `jac check` lane instead of during a full seal.

Allowlist
---------
Crossings that are known and accepted (or blocked upstream) live in
`scripts/seal-pin-allowlist.txt`, one per line:

    <module> | <importing file> | <target module> | <reason>

A reported crossing that is not listed fails the guard. A listed crossing
that no longer appears is reported as XPASS so the list cannot rot.

Usage:
    python3 scripts/seal-pin-guard.py [--app app] [--allowlist PATH]
                                      [--write-allowlist] [--strict]
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import sys
from dataclasses import dataclass, field

try:  # Python >= 3.11
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - older hosts
    tomllib = None

ANNEX_SUFFIXES = (".impl.jac", ".test.jac")

# `import from a.b { x, y }` / `import from .rel { x }` / `import a.b;`
IMPORT_FROM_RE = re.compile(r"^\s*import\s+from\s+([.\w]+)\s*(?:\{|\bas\b|;|$)")
IMPORT_PLAIN_RE = re.compile(r"^\s*import\s+([.\w]+)\s*(?:as\b|;|$)")


@dataclass
class PinConfig:
    default_space: str
    pins: dict[str, str]

    def space_of(self, module: str) -> str:
        for pattern, space in self.pins.items():
            if fnmatch.fnmatchcase(module, pattern):
                return space
        return self.default_space

    def is_hard(self, module: str) -> bool:
        """A pin that the seal refuses to demote (`"x" = "native"`)."""
        for pattern, space in self.pins.items():
            if fnmatch.fnmatchcase(module, pattern):
                return space == "native"
        return False


@dataclass
class Import:
    target: str
    names: list[str] = field(default_factory=list)
    lineno: int = 0


@dataclass
class Finding:
    module: str
    file: str
    target: str
    names: list[str]
    called: list[str]
    annex: bool

    @property
    def key(self) -> str:
        return f"{self.module} | {self.file} | {self.target}"


def parse_pins(toml_path: str) -> PinConfig:
    if tomllib is None:
        raise SystemExit("python3 >= 3.11 required (tomllib)")

    with open(toml_path, "rb") as fh:
        data = tomllib.load(fh)

    placement = data.get("placement", {})
    default_space = placement.get("default", "native")
    pins = placement.get("pins", {}) or {}
    return PinConfig(default_space=default_space, pins=dict(pins))


def module_name(app_dir: str, path: str) -> str:
    rel = os.path.relpath(path, app_dir)
    for suffix in ANNEX_SUFFIXES:
        if rel.endswith(suffix):
            rel = rel[: -len(suffix)]
            break
    else:
        rel = rel[: -len(".jac")] if rel.endswith(".jac") else rel
    return rel.replace(os.sep, ".")


def is_annex(path: str) -> bool:
    return path.endswith(ANNEX_SUFFIXES)


def module_file(app_dir: str, module: str) -> str | None:
    candidate = os.path.join(app_dir, *module.split(".")) + ".jac"
    return candidate if os.path.isfile(candidate) else None


def parse_imports(path: str) -> list[Import]:
    """Parse the import statements at the top of a Jac file.

    Jac import syntax we handle:

        import os;
        import from ui.screen { a, b };
        import from ui.screen { a,
                                b };
        import from .plugin_bridge { create_bridge };
        import from ui.width as w;
    """
    imports: list[Import] = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()

    i = 0
    while i < len(lines):
        line = lines[i]
        lineno = i + 1
        m = IMPORT_FROM_RE.match(line)
        plain = None if m else IMPORT_PLAIN_RE.match(line)
        if m is None and plain is None:
            i += 1
            continue

        if plain is not None:
            target = plain.group(1)
            imports.append(Import(target=target, names=[], lineno=lineno))
            i += 1
            continue

        target = m.group(1)
        names: list[str] = []
        # Everything after the target on this line, plus following lines when
        # a `{ ... }` name list is opened.
        rest = line[m.end(1) :]
        if "{" in rest:
            chunk = rest.split("{", 1)[1]
            while "}" not in chunk and i + 1 < len(lines):
                i += 1
                chunk += lines[i]
            body = chunk.split("}", 1)[0]
            for raw in body.split(","):
                name = raw.strip().split(" as ")[0].strip()
                if name:
                    names.append(name)
        imports.append(Import(target=target, names=names, lineno=lineno))
        i += 1
    return imports


def resolve_target(app_dir: str, importer: str, target: str) -> str | None:
    """Return the dotted module a target resolves to, or None for stdlib."""
    if target.startswith("."):
        depth = len(target) - len(target.lstrip("."))
        rest = target.lstrip(".")
        base_parts = module_name(app_dir, importer).split(".")[:-1]
        if depth > 1:
            base_parts = base_parts[: -(depth - 1)] if depth - 1 <= len(base_parts) else []
        parts = base_parts + ([p for p in rest.split(".") if p])
        dotted = ".".join(parts)
        return dotted if module_file(app_dir, dotted) else None
    head = target.split(".")[0]
    if module_file(app_dir, target) is None and module_file(app_dir, head) is None:
        return None  # stdlib / third-party
    return target


def called_names(lines: list[str], names: list[str], import_line: int) -> list[str]:
    """Names from an import that the file actually calls or constructs."""
    if not names:
        return []
    used: list[str] = []
    for lineno, line in enumerate(lines, 1):
        if lineno == import_line:
            continue
        if line.lstrip().startswith("#"):
            continue
        for name in names:
            if name in used:
                continue
            if re.search(rf"\b{re.escape(name)}\s*\(", line):
                used.append(name)
    return used


def collect(app_dir: str, config: PinConfig) -> list[Finding]:
    findings: list[Finding] = []
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = sorted(
            d for d in dirs if d not in {".jac", "node_modules", "__pycache__", ".git"}
        )
        for fname in sorted(files):
            if not fname.endswith(".jac"):
                continue
            path = os.path.join(root, fname)
            rel = os.path.relpath(path, app_dir).replace(os.sep, "/")
            if rel.startswith(".jac/"):
                continue
            module = module_name(app_dir, path)
            if not config.is_hard(module):
                continue
            imports = parse_imports(path)
            if not imports:
                continue
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
            for imp in imports:
                dotted = resolve_target(app_dir, path, imp.target)
                if dotted is None:
                    continue
                if config.space_of(dotted) != "server":
                    continue
                findings.append(
                    Finding(
                        module=module,
                        file=rel,
                        target=dotted,
                        names=list(imp.names),
                        called=called_names(lines, imp.names, imp.lineno),
                        annex=is_annex(path),
                    )
                )
    return findings


def load_allowlist(path: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not os.path.isfile(path):
        return entries
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 3:
                continue
            reason = parts[3] if len(parts) > 3 else ""
            entries[" | ".join(parts[:3])] = reason
    return entries


def main(argv: list[str]) -> int:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--app", default=os.path.join(repo, "app"))
    ap.add_argument(
        "--allowlist", default=os.path.join(repo, "scripts", "seal-pin-allowlist.txt")
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="fail on any crossing, including imported-but-not-called ones",
    )
    ap.add_argument(
        "--write-allowlist",
        action="store_true",
        help="rewrite the allowlist from the current findings (review the diff!)",
    )
    args = ap.parse_args(argv)

    config = parse_pins(os.path.join(args.app, "jac.toml"))
    findings = collect(args.app, config)

    # A crossing only *provably* fails the seal when a non-C-ABI name is used;
    # an unused or type-only import stays a warning.
    hard = [f for f in findings if f.called]
    soft = [f for f in findings if not f.called]
    if args.strict:
        hard, soft = findings, []

    if args.write_allowlist:
        existing = load_allowlist(args.allowlist)
        lines = [
            "# Crossings a hard native pin may not take (see scripts/seal-pin-guard.py).",
            "# Format: <module> | <importing file> | <target module> | <reason>",
            "#",
            "# Every entry is a known native->server reference made from a module pinned",
            "# `\"x\" = \"native\"` in app/jac.toml (including its .impl.jac / .test.jac",
            "# annexes, which the seal folds into the module's native unit). A `called`",
            "# entry fails the seal with E5093 unless the signature is C-ABI only; an",
            "# imported-but-uncalled entry is a latent risk once a call site appears.",
            "#",
            "# Keep this list empty unless a crossing is genuinely unavoidable. An entry",
            "# that stops crossing is reported as XPASS — delete it then.",
            "",
        ]
        for f in sorted(findings, key=lambda x: x.key):
            reason = existing.get(f.key)
            if not reason:
                reason = (
                    "TODO: calls " + ",".join(f.called)
                    if f.called
                    else "TODO: type/name only"
                )
            lines.append(f"{f.key} | {reason}")
        with open(args.allowlist, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"wrote {args.allowlist} ({len(findings)} crossings)")
        return 0

    allowed = load_allowlist(args.allowlist)
    unexpected = [f for f in hard if f.key not in allowed]

    if findings:
        print(f"hard native pins with server imports: {len(findings)}")
        print(f"  {'state':<9} {'module':<28} {'file':<34} target")
        for f in sorted(findings, key=lambda x: x.key):
            if f.key in allowed:
                state = "allowed"
            elif f.called:
                state = "CALLED"
            else:
                state = "imported"
            print(
                f"  {state:<9} {f.module:<28} {f.file:<34} {f.target}"
                + (f"  [{', '.join(f.called)}]" if f.called else "")
            )

    stale = sorted(set(allowed) - {f.key for f in findings})
    if stale:
        print()
        for key in stale:
            print(f"::warning::seal-pin allowlist entry no longer crosses: {key}")
            print(f"XPASS {key}")

    if unexpected:
        print()
        for f in unexpected:
            verb = (
                f"calls {', '.join(f.called)} in"
                if f.called
                else "imports"
            )
            print(
                f"::error file=app/{f.file}::hard native pin '{f.module}' "
                f"{verb} '{f.target}' from {f.file}; the seal will fail with "
                f"E5093 unless that signature is C-ABI only. Move the case to a "
                f"server-placed suite, or add a reviewed allowlist entry."
            )
        print()
        print(
            f"FAIL: {len(unexpected)} unlisted native->server call(s) under a hard pin."
        )
        return 1

    print()
    print("OK: no unlisted native->server calls under a hard native pin.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
