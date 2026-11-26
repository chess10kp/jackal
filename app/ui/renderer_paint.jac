def _blank_buffer(columns: int, rows: int) -> CellBuffer;

def _paint_text_into(
    buf: CellBuffer, text: str, row: int, col: int, max_width: int, attrs: StyleAttrs | None = None
);

def _paint_entry_lines(buf: CellBuffer, layout_entry: FrameEntry, scrolls: bool);
def _overlay_z_key(hit: _OverlayHit) -> int;

def _overlay_jid_key(hit: _OverlayHit) -> str;

def _layered_overlays(layout_root: UiNode) -> list[UiNode];

def _paint_node(state: LayoutState, n: UiNode, buf: CellBuffer);

def _paint_tree(state: LayoutState, n: UiNode, buf: CellBuffer);

def _paint_frame_buffer(renderer: Renderer, layout_root: UiNode) -> CellBuffer;
