"""Process wrapper for the Node SSE fixture used by llm transport tests."""

import os;
import subprocess;
import io;
import time;


obj SseTestServer {
    has proc: subprocess.Popen | None = None,
        server_port: int = 0;

    def shutdown() -> None {
        if self.proc is not None {
            proc: subprocess.Popen = self.proc as subprocess.Popen;
            if proc.poll() is None {
                proc.terminate();
                try { proc.wait(timeout=5.0); } except Exception {
                    proc.kill();
                    try { proc.wait(timeout=5.0); } except Exception { }
                }
            }
            self.proc = None;
        }
    }
}


def make_sse_server(mode: str = "ok") -> SseTestServer {
    fixture: str = os.path.abspath(os.path.join(
        os.getcwd(), "agent", "sse_test_server.mjs"
    ));
    node_bin: str = os.environ.get("JACKAL_NODE_BIN", "node");
    ready_file: str = os.path.join(
        os.getcwd(),
        ".jackal-sse-" + str(os.getpid()) + "-" + str(time.monotonic_ns()) + ".port",
    );
    proc: subprocess.Popen = subprocess.Popen(
        [node_bin, fixture, mode, ready_file],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    );
    deadline: float = time.monotonic() + 5.0;
    while not os.path.exists(ready_file) and time.monotonic() < deadline {
        if proc.poll() is not None {
            break;
        }
        time.sleep(0.01);
    }
    if not os.path.exists(ready_file) {
        proc.terminate();
        try { proc.wait(timeout=5.0); } except Exception { proc.kill(); }
        raise RuntimeError("SSE fixture did not create its ready file");
    }
    fh: io.FileIO = io.FileIO(ready_file, "rb");
    ready: str = fh.read().decode("utf-8").strip();
    fh.close();
    os.remove(ready_file);
    if not ready.isdigit() {
        proc.terminate();
        try { proc.wait(timeout=5.0); } except Exception { proc.kill(); }
        raise RuntimeError("SSE fixture returned an invalid port: " + ready);
    }
    return SseTestServer(proc=proc, server_port=int(ready));
}
