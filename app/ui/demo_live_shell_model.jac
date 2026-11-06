"""State model shared by the live shell facade and its helper modules."""

import from ui.runtime { UiSession }
import from ui.transcript { TranscriptMessage, TranscriptProjection }
import from ui.renderer { Renderer }
import from ui.terminal { ProcessTerminal }
import from ui.screen { ShellScreen }
import from ui.input { InputNormalizer }
import from ui.progress_bar { ProgressBar }


obj:pub LiveShell {
    has session: UiSession,
        # `shell`/`normalizer` are `any`: their real types (ShellScreen in
        # ui.screen, InputNormalizer in ui.input) are server-pinned, and a
        # shared native unit cannot import them at all — they erase to
        # opaque slots in the native layout either way.
        shell: ShellScreen,
        normalizer: InputNormalizer,
        proj: TranscriptProjection,
        renderer: Renderer,
        term: ProcessTerminal,
        progress: ProgressBar,
        messages: list[TranscriptMessage] = [],
        rev: int = 0,
        msg_n: int = 0,
        phase: str = "ready",
        progress_value: float = 0.0,
        stream_full: str = "",
        stream_shown: int = 0,
        stream_msg_id: str = "",
        stream_tick: int = 0,
        spin_i: int = 0,
        running: bool = True,
        dirty: bool = True,
        columns: int = 80,
        rows: int = 24,
        status_hint: str = "enter · ↑↓ history · esc quit";
}


"""Factory seam for the live shell demo's typed native state."""
def:pub make_live_shell(
    session: UiSession,
    shell: ShellScreen,
    proj: TranscriptProjection,
    renderer: Renderer,
    term: ProcessTerminal,
    normalizer: InputNormalizer,
    progress: ProgressBar,
    columns: int,
    rows: int,
) -> LiveShell {
    return LiveShell(
        session=session,
        shell=shell,
        proj=proj,
        renderer=renderer,
        term=term,
        normalizer=normalizer,
        progress=progress,
        columns=columns,
        rows=rows,
    );
}
