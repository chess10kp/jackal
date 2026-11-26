def _install_shell_layout(renderer: Renderer, shell: ShellScreen, columns: int, rows: int);

def _paint_shell(
    renderer: Renderer,
    shell: ShellScreen,
    header_line: str,
    transcript_lines: list[str],
    status_line: str,
    prompt_lines: list[str],
    overlay_lines: list[str] | None = None,
);
