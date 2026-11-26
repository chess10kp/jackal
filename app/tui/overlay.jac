import os;
def _approval_diff_preview(name: str, args: dict[str, any]) -> list[str];
def _approval_lines(app: LiveShell) -> list[str];
def _ui_modal_lines(app: LiveShell) -> list[str];
def _picker_popup_rows(app: LiveShell) -> list[str];
def _ui_select_popup_rows(app: LiveShell) -> list[str];
def _paint_overlay(app: LiveShell, lines: list[str], outer_width: int = 48);
def _model_completion_candidates(prefix: str) -> list[list[str]];
def _popup_suppressed(raw: str, dismissed: str) -> bool;
def _slash_popup_state(app: LiveShell) -> list[list[str]] | None;
def _slash_popup_pick(matches: list[list[str]], draft: str, sel: int) -> tuple[str, bool];
def _slash_popup_rows(app: LiveShell, matches: list[list[str]]) -> list[str];

def _transcript_lines(app: LiveShell) -> list[str];

def _paint(app: LiveShell);

def _render(app: LiveShell);
