def compile_layout(
    state: LayoutState,
    layout_root: UiNode,
    viewport: Viewport,
    natural_sizes: dict[str, Size] = {},
    phase: str = "full",
) -> CompileResult;

def compile_scoped_layout(
    state: LayoutState,
    scope: _Scope,
    root_id: str,
    viewport: Viewport,
    natural_sizes: dict[str, Size],
    phase: str,
) -> CompileResult;
def collect_scope_for_engine(layout_root: UiNode) -> _Scope;
