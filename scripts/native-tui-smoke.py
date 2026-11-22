#!/usr/bin/env python3
"""Drive a natively built Jackal TUI binary in a PTY (mock model) and print the screen tail."""
import os, pty, re, select, sys, time, struct, fcntl, termios
binary = sys.argv[1]
steps = sys.argv[2:] or ["hello there", "\r", "/exit\r"]
pid, fd = pty.fork()
if pid == 0:
    os.environ.setdefault("TERM", "xterm-256color")
    os.execv(binary, [binary])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
out = b""
def rd(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                out += os.read(fd, 65536)
            except OSError:
                return
rd(6)
for s in steps:
    os.write(fd, s.encode()); rd(2.5)
rd(2)
alive = True
try:
    wpid, st = os.waitpid(pid, os.WNOHANG); alive = wpid == 0
    if alive: os.kill(pid, 9)
except ChildProcessError:
    alive = False
txt = re.sub(rb"\x1b\[[0-9;?<>=]*[a-zA-Z~]|\x1b[()][0-9A-B]|\x1b\][^\x07]*\x07|\x1b[=>78]", b"", out).decode("utf-8", "replace")
print("bytes:", len(out), "still_running:", alive)
print(txt[-int(os.environ.get("TAIL", "3000")):])
