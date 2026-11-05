"""Core layout value types for the public ui.layout_types seam.

The public module re-exports these declarations together with registry
lifecycle operations. Keeping the data model independent avoids import cycles.
"""

import from constraints.algebra {
    StrengthTier,
    is_finite,
}
import from ui.model {
    UiNode,
    node_id,
}


"""Axis-aligned terminal rectangle in cell coordinates (origin top-left)."""
obj:pub Rect {
    has x: int = 0,
        y: int = 0,
        width: int = 0,
        height: int = 0;

    def right() -> int {
        return self.x + self.width;
    }

    def bottom() -> int {
        return self.y + self.height;
    }

    def is_empty() -> bool {
        return self.width <= 0 or self.height <= 0;
    }

    def contains_point(col: int, row: int) -> bool {
        return (
            col >= self.x
            and col < self.right()
            and row >= self.y
            and row < self.bottom()
        );
    }

    def intersects(other: Rect) -> bool {
        if self.is_empty() or other.is_empty() {
            return False;
        }
        return (
            self.x < other.right()
            and self.right() > other.x
            and self.y < other.bottom()
            and self.bottom() > other.y
        );
    }

    def copy() -> Rect {
        return Rect(
            x=self.x,
            y=self.y,
            width=self.width,
            height=self.height,
        );
    }
}


obj:pub Size {
    has width: int = 0,
        height: int = 0;
}


def:pub rect_union(a: Rect, b: Rect) -> Rect {
    if a.is_empty() {
        return b.copy();
    }
    if b.is_empty() {
        return a.copy();
    }
    x0 = min(a.x, b.x);
    y0 = min(a.y, b.y);
    x1 = max(a.right(), b.right());
    y1 = max(a.bottom(), b.bottom());
    return Rect(x=x0, y=y0, width=x1 - x0, height=y1 - y0);
}


enum:pub Axis { HORIZONTAL = "horizontal", VERTICAL = "vertical" }
enum:pub SizeMode { FIXED = "fixed", INTRINSIC = "intrinsic", BOUNDED = "bounded", FILL = "fill", GROW = "grow" }
enum:pub Align { START = "start", CENTER = "center", END = "end", STRETCH = "stretch" }
enum:pub OverlayAnchor { CENTER = "center", TOP = "top", BOTTOM = "bottom", LEFT = "left", RIGHT = "right" }


"""Per-axis sizing policy (plan §4.1)."""
obj:pub AxisSize {
    has mode: SizeMode,
        minimum: float = 0.0,
        preferred: float | None = None,
        maximum: float | None = None,
        grow_weight: float = 0.0;
}


"""Permanent node layout spec (plan §4.1).

Field order puts the required axis sizes first because Jac objects follow
dataclass default rules (a plan-sanctioned spelling change)."""
obj:pub LayoutSpec {
    has width: AxisSize,
        height: AxisSize,
        flow_axis: Axis = Axis.VERTICAL,
        cross_align: Align = Align.STRETCH,
        scroll_vertical: bool = False,
        overlay_anchor: OverlayAnchor | None = None;
}


enum:pub LayoutSeverity { WARNING = "warning", ERROR = "error" }
enum:pub LayoutError {
    INVALID_SPEC = "invalid_spec",
    INVALID_RELATION = "invalid_relation",
    STALE_NODE = "stale_node",
    OUT_OF_SCOPE = "out_of_scope",
    INVALID_TOPOLOGY = "invalid_topology",
    UNSATISFIABLE = "unsatisfiable",
    OVERFLOW = "overflow",
    UNSUPPORTED_AXIS_COUPLING = "unsupported_axis_coupling",
    INTERNAL_INVARIANT = "internal_invariant"
}


obj:pub Viewport {
    has columns: int,
        rows: int;
}


obj:pub RelationHandle {
    has id: int;
}


obj:pub LayoutDiagnostic {
    has code: LayoutError,
        severity: LayoutSeverity,
        message: str,
        node_ids: list[str] = [],
        provenance: list[str] = [];
}


obj:pub FrameEntry {
    has measured: Size,
        rect: Rect,
        clip: Rect,
        wrapped_lines: list[str],
        requested_scroll_offset: int = 0,
        scroll_offset: int = 0,
        max_scroll_offset: int = 0;
}


obj:pub LayoutFrame {
    has generation: int,
        viewport: Viewport,
        entries: dict[str, FrameEntry],
        overlay_ids: list[str];
}


obj:pub MutationResult {
    has ok: bool,
        relation_handle: RelationHandle | None = None,
        diagnostics: list[LayoutDiagnostic] = [];
}


obj:pub LayoutResult {
    has ok: bool,
        frame: LayoutFrame | None = None,
        diagnostics: list[LayoutDiagnostic] = [];
}


enum:pub LayoutRelationKind {
    LEFT_OF = "left_of", RIGHT_OF = "right_of",
    ABOVE = "above", BELOW = "below",
    ALIGN_START = "align_start", ALIGN_END = "align_end",
    ALIGN_CENTER = "align_center", SAME_SIZE = "same_size"
}


"""Process-local spatial relation between two live nodes (plan §4.1).

Not an OSP edge: relations are registry data keyed by stable node ids so
a replaced node (new jid) never inherits geometry declarations."""
obj:pub LayoutRelation {
    has owner_id: str,
        source_id: str,
        target_id: str,
        kind: LayoutRelationKind,
        axis: Axis,
        provenance: str,
        gap: float = 0.0,
        strength: StrengthTier = StrengthTier.REQUIRED;
}


"""Registered content for one node (plan §4 invariant 6)."""
obj:pub ContentEntry {
    has lines: list[str],
        content_revision: int,
        style_revision: int;
}


"""Cached wrapped lines for one node at one integer width (plan §7.1
step 4). One entry per node — revisions are monotonic, so older wraps
are never reusable and keeping only the newest bounds memory."""
obj:pub MeasureEntry {
    has width: int,
        content_revision: int,
        style_revision: int,
        lines: list[str];
}


"""Permanent layout registry (plan §4).

`solver` and `last_frame` carry solver state and the last published
frame. Frames are immutable by ownership convention."""
obj:pub LayoutState {
    has viewport: Viewport = Viewport(columns=80, rows=24),
        specs: dict[str, LayoutSpec] = {},
        content: dict[str, ContentEntry] = {},
        relations: dict[int, LayoutRelation] = {},
        next_relation_id: int = 1,
        measurement_cache: dict[str, MeasureEntry] = {},
        scroll_requests: dict[str, int] = {},
        last_frame: LayoutFrame | None = None;
}


# ----------------------------------------------------------------------
# Spec construction helpers (axis sugar over AxisSize).
# ----------------------------------------------------------------------
