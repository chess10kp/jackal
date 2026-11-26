import from time { perf_counter }

obj DemoStep {
    has name: str,
        ok: bool,
        detail: str = "";
}

obj DemoReport {
    has passed: bool = False,
        steps: list[DemoStep] = [],
        cells_written_total: int = 0,
        coalesced_deltas: int = 0,
        frames_rendered: int = 0,
        invariant_findings: int = 0,
        stable_ids: bool = False,
        disposed_clean: bool = False,
        latency_ms: float = 0.0,
        last_frame: str = "",
        graph_dump: str = "",
        binding_dump: str = "";
}

def _step(demo: DemoReport, name: str, ok: bool, detail: str = "");

def _frame_text(rows: list[str]) -> str;
def run_complex_shell_demo(columns: int = 80, rows: int = 24, verbose: bool = False) -> DemoReport;
def format_demo_report(demo: DemoReport) -> str;

with entry {
    demo = run_complex_shell_demo(verbose=False);
    print(format_demo_report(demo));
    if not demo.passed {
        failed = [s.name for s in demo.steps if not s.ok];
        raise SystemExit("demo failed: " + ", ".join(failed));
    }
}
