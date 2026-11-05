"""Process wrapper for the Node SSE fixture used by llm transport tests."""

import os;
import subprocess;


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
    proc: subprocess.Popen = subprocess.Popen(
        [node_bin, fixture, mode],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    );
    out_pipe: any = proc.stdout;
    ready: str = out_pipe.readline().strip();
    if not ready.startswith("READY ") {
        proc.terminate();
        try { proc.wait(timeout=5.0); } except Exception { proc.kill(); }
        raise RuntimeError("SSE fixture did not start: " + ready);
    }
    return SseTestServer(proc=proc, server_port=int(ready.split(" ")[1]));
}
