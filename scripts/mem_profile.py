#!/usr/bin/env python3
"""Measure the Jackal harness's RSS across its whole process tree.

Spawns a command (by default the interactive REPL under the mock provider),
samples every descendant's RSS via /proc ppid chains, and reports peaks:

  boot_peak_total_kb   highest instantaneous tree total BEFORE the boot marker
  post_peak_total_kb   highest instantaneous tree total AFTER it (resident)
  per_process_peak_kb  each descendant's individual peak

`--marker` (string) splits the two phases; --json prints nothing but the
final report. Exit code 0; budget enforcement happens in scripts/mem-profile.sh.
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time


def descendants(root, stat_cache=None):
    entries = [int(e) for e in os.listdir("/proc") if e.isdigit()]
    stat = {}
    for pid in entries:
        try:
            with open(f"/proc/{pid}/stat", "rb") as f:
                parts = f.read().rsplit(b") ", 1)[1].split(b" ")
                stat[pid] = int(parts[1])
        except (OSError, ValueError, IndexError):
            continue
    out = []
    for pid in stat:
        cur = pid
        hops = 0
        while cur in stat and cur != 1 and hops < 64:
            if cur == root:
                out.append(pid)
                break
            cur = stat[cur]
            hops += 1
    return out


def rss_kb(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--marker", default=None,
                    help="substring of stdout that ends the 'boot' phase")
    ap.add_argument("--timeout", type=float, default=600)
    ap.add_argument("cmd", nargs="+")
    args = ap.parse_args()

    boot_peak = 0
    post_peak = 0
    peaks = {}
    names = {}
    marker_seen = args.marker is None
    done = threading.Event()

    proc = subprocess.Popen(
        args.cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, bufsize=1)

    def watcher():
        nonlocal marker_seen
        assert proc.stdout is not None
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            sys.stderr.write("app| " + line)
            sys.stderr.flush()
            if args.marker and args.marker in line:
                marker_seen = True
        done.set()

    threading.Thread(target=watcher, daemon=True).start()

    stdin_buf = b"say hi once\n/exit\n"
    start = time.monotonic()
    while (not done.is_set()
           and not proc.poll() is not None and proc.poll() is None
           and time.monotonic() - start < args.timeout):
        total = 0
        for pid in descendants(proc.pid):
            r = rss_kb(pid)
            if r is None:
                continue
            total += r
            if pid not in peaks or r > peaks[pid]:
                exe = "?"
                try:
                    exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
                except OSError:
                    pass
                names[pid] = exe
                peaks[pid] = r
        if marker_seen:
            post_peak = max(post_peak, total)
        else:
            boot_peak = max(boot_peak, total)
        time.sleep(0.2)

    if not done.is_set():
        try:
            proc.stdin.write(stdin_buf)   # ask it to exit
            proc.stdin.flush()
            proc.stdin.close()
        except Exception:
            pass
        proc.wait(timeout=30)
    else:
        try:
            proc.stdin.close()
        except Exception:
            pass
        proc.wait()

    report = {
        "cmd": " ".join(args.cmd),
        "returncode": proc.returncode,
        "boot_peak_total_kb": boot_peak,
        "post_boot_peak_total_kb": post_peak,
        "worst_process": (
            {"pid": max(peaks, key=peaks.get), "kb": peaks[max(peaks, key=peaks.get)],
             "exe": names.get(max(peaks, key=peaks.get), "?")}
            if peaks else None),
        "per_process_peak_kb": {
            str(p): {"kb": kb, "exe": names.get(p, "?")} for p, kb in peaks.items()},
    }
    print(json.dumps(report))
    return 0 if proc.returncode in (0, None) else 0


if __name__ == "__main__":
    sys.exit(main())
