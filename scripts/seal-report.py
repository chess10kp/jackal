#!/usr/bin/env python3
"""Summarize a `jac build` log into the seal-wall table.

The seal prints hundreds of lines of per-element demotions before it decides
whether the artifact ships. This reduces a run to the few facts that matter:

  * hard walls — units whose hard native pin could not lower (these fail the
    build);
  * root causes — the source files the demotion diagnostics actually point at,
    ranked; a cascade is usually one root (an erased field or an unlowerable
    signature) fanning out through importers;
  * erased fields — a field whose declared type could not be lowered, listed
    separately because it is a root;
  * the seal abort — the E-code and symbol that stopped the build;
  * soft module demotions — modules that preferred native and were compiled
    in the server codespace (allowed, but each is distance from N6).

Usage:
    ../jac build > /tmp/seal.log 2>&1 || true
    python3 scripts/seal-report.py /tmp/seal.log
    python3 scripts/seal-report.py --json /tmp/seal.log
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, OrderedDict

RE_UNIT = re.compile(r"\[\s*(\d+)/\d+\]\s+(\S+\.jac)")
RE_HARD = re.compile(r"FAIL \(native unit did not lower\):\s*(\S+\.jac)")
RE_SOFT = re.compile(
    r"note:\s*(\S+\.jac)\s+preferred native but did not lower; compiled in the "
    r"server codespace \((error\[(E\d+)\]:\s*([^)]*))\)"
)
RE_DEMOTE = re.compile(
    r"native seam -- demoting (\S+) to Python-only \(un-lowerable\):\s*(.*)"
)
RE_ERASE = re.compile(
    r"native seam -- erasing field (\S+)\.(\S+) to an opaque slot "
    r"\(un-lowerable declaration\):\s*(.*)"
)
RE_ABORT = re.compile(r"Error: Seal aborted:\s*(.*)")
RE_ERR = re.compile(r"error\[(E\d+)\]:\s*(.*)")
RE_SEAL_FAILED = re.compile(r"Error: Seal failed")
RE_CAUSE_FILE = re.compile(r"([\w./-]+\.jac), line (\d+), col (\d+): (.*)")


def _cause_key(diag: str) -> tuple[str, str]:
    """(file, message) for a located diagnostic, else the raw text."""
    m = RE_CAUSE_FILE.search(diag)
    if not m:
        return ("<unlocated>", diag.strip()[:120])
    return (m.group(1).split("/")[-1], m.group(4).strip())


def summarize(lines: list[str]) -> dict:
    unit = ""
    failures: "OrderedDict[str, int]" = OrderedDict()
    soft: "OrderedDict[str, str]" = OrderedDict()
    erased: "OrderedDict[str, list[str]]" = OrderedDict()
    demotions: Counter = Counter()
    cause_files: Counter = Counter()
    cause_examples: "OrderedDict[str, str]" = OrderedDict()
    first_cause_for_unit: dict[str, str] = {}
    abort = ""
    codes: "OrderedDict[str, str]" = OrderedDict()
    seal_failed = False

    for raw in lines:
        line = raw.rstrip("\n")
        m = RE_UNIT.search(line)
        if m:
            unit = m.group(2)
        m = RE_HARD.search(line)
        if m:
            failures.setdefault(m.group(1), 0)
            continue
        m = RE_SOFT.search(line)
        if m:
            why = f"{m.group(3)}: {m.group(4).strip()}" if m.group(4) else m.group(2)
            soft[m.group(1)] = why
            continue
        m = RE_ERASE.search(line)
        if m:
            arch_field = f"{m.group(1)}.{m.group(2)}"
            why = re.split(r"[;]", m.group(3))[0].strip()
            erased.setdefault(arch_field, [])
            if why and why not in erased[arch_field]:
                erased[arch_field].append(why)
            continue
        m = RE_DEMOTE.search(line)
        if m:
            why = m.group(2)
            demotions[unit] += 1
            if unit in failures:
                failures[unit] += 1
            for diag in re.split(r";\s*(?=/|[A-Za-z_][\w./-]*\.jac, line)", why):
                (fname, msg) = _cause_key(diag)
                cause_files[fname] += 1
                cause_examples.setdefault(f"{fname}: {msg}", diag.strip()[:200])
                if unit in failures and unit not in first_cause_for_unit:
                    first_cause_for_unit[unit] = f"{fname}: {msg}"
            continue
        m = RE_ABORT.search(line)
        if m:
            abort = m.group(1).strip()
            continue
        m = RE_ERR.search(line)
        if m:
            codes.setdefault(m.group(1), m.group(2).strip())
            continue
        if RE_SEAL_FAILED.search(line):
            seal_failed = True

    return {
        "hard_units": dict(failures),
        "hard_units_first_cause": first_cause_for_unit,
        "soft_modules": {
            path.split("/")[-1]: why for path, why in soft.items()
        },
        "erased_fields": dict(erased),
        "demotions_by_unit": dict(demotions.most_common()),
        "cause_files": dict(cause_files.most_common()),
        "cause_examples": dict(list(cause_examples.items())[:12]),
        "abort": abort[:600],
        "codes": codes,
        "seal_failed": seal_failed,
    }


def print_report(data: dict) -> None:
    hard = data["hard_units"]
    soft = data["soft_modules"]
    erased = data["erased_fields"]

    print("=" * 78)
    print("HARD WALLS (the seal cannot complete)")
    print("=" * 78)
    if hard:
        first = data["hard_units_first_cause"]
        for unit, demotions in hard.items():
            print(f"  {unit}  ({demotions} demoted element(s) in this unit)")
            if unit in first:
                print(f"      first: {first[unit]}")
    else:
        print("  (none recorded)")

    if data["cause_files"]:
        print()
        print("ROOT CAUSES (source files the demotion diagnostics point at)")
        for fname, count in list(data["cause_files"].items())[:8]:
            examples = [
                ex
                for key, ex in data["cause_examples"].items()
                if key.startswith(f"{fname}: ")
            ]
            print(f"  {count:4d}  {fname}")
            for ex in examples[:2]:
                print(f"          {ex}")

    if erased:
        print()
        print("ERASED FIELDS (a field type that would not lower)")
        for arch_field, whys in erased.items():
            print(f"  {arch_field}")
            for why in whys[:3]:
                print(f"          {re.sub(r'/tmp/[^/]+/jackal/', '', why)}")

    if soft:
        print()
        print("SOFT MODULE DEMOTIONS (allowed; each is distance from N6)")
        for module, why in soft.items():
            print(f"  {module}: {why}")

    print()
    print("=" * 78)
    if data["abort"]:
        abort = re.sub(r"/tmp/[^/]+/jackal/", "", data["abort"])
        print(f"SEAL ABORT: {abort[:400]}")
    if data["codes"]:
        for code, text in data["codes"].items():
            print(f"  {code}: {text[:200]}")
    if not data["abort"] and not data["seal_failed"]:
        print("(no seal abort found — build may have succeeded or the log is partial)")
    print("=" * 78)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", nargs="?", help="build log (default: stdin)")
    ap.add_argument("--json", action="store_true", help="emit the raw summary as JSON")
    args = ap.parse_args(argv)

    if args.log:
        with open(args.log, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    else:
        lines = sys.stdin.readlines()

    data = summarize(lines)
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        print_report(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
