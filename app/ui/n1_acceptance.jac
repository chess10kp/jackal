obj N1Result {
    has name: str = "",
        ok: bool = False,
        detail: str = "";
}

def _check(name: str, ok: bool, detail: str = "") -> N1Result;

def _wire_shell_content(renderer: Renderer, shell: ShellScreen, transcript: str, prompt: str);

def scenario_first_paint_no_full_clear -> N1Result;

def scenario_resize_mid_stream -> N1Result;

def scenario_cancel_clears_draft -> N1Result;

def scenario_protocol_cancel_drive -> N1Result;

def scenario_esc_timeout -> N1Result;

def scenario_host_interrupt_effect -> N1Result;

def scenario_restore_idempotent -> N1Result;

def scenario_process_terminal_flag_restore -> N1Result;

def scenario_pty_soak_virtual -> N1Result;

def scenario_second_frame_retained -> N1Result;

def run_n1_acceptance -> bool;

test "n1 acceptance suite passes" {
    assert run_n1_acceptance();
}

with entry {
    ok = run_n1_acceptance();
    if not ok {
        raise SystemExit(1);
    }
}
