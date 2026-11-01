#!/usr/bin/env python3
"""Measure a command's RSS across its process tree, splitting boot from idle.

Spawns the command (default usage is the Jackal REPL) with scripted stdin:
one real turn, then a quiet window, then /exit. Samples every descendant's
RSS and reports:

  tree_peak_kb   highest instantaneous tree total over the whole run
  idle_kb        tree total at the last sample (steady-state resident)
  per_process_peak_kb

The boot marker only annotates (child stdout may be block-buffered, so it is
not reliable for phase splitting); the idle number is the resident metric.

Linux uses /proc; macOS falls back to `ps`.
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time

DARWIN = sys.platform == "darwin"


def tree_pids(root):
    parents = {}
    if DARWIN:
        try:
            out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=", "-ww"],
                                 capture_output=True, text=True, timeout=5).stdout
        except OSError:
            return []
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 2:
                try:
                    parents[int(parts[0])] = int(parts[1])
                except ValueError:
                    pass
    else:
        for e in os.listdir("/proc"):
            if not e.isdigit():
                continue
            try:
                with open(f"/proc/{e}/stat", "rb") as f:
                    parts = f.read().rsplit(b") ", 1)[1].split(b" ")
                parents[int(e)] = int(parts[1])
            except (OSError, ValueError, IndexError):
                continue
    found = []
    for pid in parents:
        cur, hops = pid, 0
        while cur in parents and cur != 1 and hops < 64:
            if cur == root:
                found.append(pid)
                break
            cur = parents[cur]
            hops += 1
    return found


def rss_kb(pid):
    if DARWIN:
        try:
            out = subprocess.run(["ps", "-p", str(pid), "-o", "rss="],
                                 capture_output=True, text=True, timeout=5).stdout
            return int(out.split()[0]) if out.split() else None
        except (OSError, ValueError, IndexError):
            return None
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
    ap.add_argument("--idle-seconds", type=float, default=8.0,
                    help="quiet window after the first turn (default 8)")
    ap.add_argument("--timeout", type=float, default=600)
    ap.add_argument("cmd", nargs="+")
    args = ap.parse_args()

    proc = subprocess.Popen(
        args.cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, bufsize=1)

    def writer():
        try:
            proc.stdin.write("say hi\n")
            proc.stdin.flush()
            time.sleep(args.idle_seconds)
            proc.stdin.write("/exit\n")
            proc.stdin.flush()
            proc.stdin.close()
        except (BrokenPipeError, ValueError):
            pass

    threading.Thread(target=writer, daemon=True).start()

    def drain():
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stderr.write("app| " + line)
            sys.stderr.flush()

    threading.Thread(target=drain, daemon=True).start()

    peak = 0
    last = 0
    samples = 0
    peaks = {}
    names = {}
    start = time.monotonic()
    while proc.poll() is None and time.monotonic() - start < args.timeout:
        total = 0
        for pid in tree_pids(proc.pid):
            r = rss_kb(pid)
            if r is None:
                continue
            total += r
            if pid not in peaks or r > peaks[pid]:
                peaks[pid] = r
                try:
                    names[pid] = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
                except OSError:
                    names[pid] = "?"
        if total:
            peak = max(peak, total)
            last = total
            samples += 1
        time.sleep(0.2)

    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    worst = max(peaks, key=peaks.get) if peaks else None
    print(json.dumps({
        "cmd": " ".join(args.cmd),
        "returncode": proc.returncode,
        "samples": samples,
        "tree_peak_kb": peak,
        "idle_kb": last,
        "worst_process": ({"pid": worst, "kb": peaks[worst],
                           "exe": names.get(worst, "?")} if worst else None),
        "per_process_peak_kb": {
            str(p): {"kb": kb, "exe": names.get(p, "?")} for p, kb in peaks.items()},
    }))


if __name__ == "__main__":
    main()
