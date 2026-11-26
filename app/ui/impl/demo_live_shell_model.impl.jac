impl make_live_shell(
    session: UiSession,
    shell: any,
    proj: TranscriptProjection,
    renderer: Renderer,
    term: ProcessTerminal,
    normalizer: any,
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
