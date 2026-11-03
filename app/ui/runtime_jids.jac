"""Persistent-root reachability probe — server-only seed shim.

`root` is the one OSP surface with no native lowering yet (upstream
#10545), and it is a placement blocker that marks the WHOLE module
non-native (PERSIST), which erased every signature type UiSession
carries into native units — with placement pins unable to override
that gate (upstream #10546). This file therefore holds only the
`root`-adjacent hop: it enumerates `[root -->]` on the server, then
hands typed `NodeArchetype` seeds to the native BFS in ui.osp_walk.
Callers are server modules only — native code must not call it
across the boundary.
"""

import from ui.osp_walk { ui_jids_reachable_from_nodes }


"""One-hop enumeration of persistent root's edges as seed handles.

Covers both directions: the BFS itself walks `-->` and `<--`, so seeds
must include nodes that edge INTO root as well as root's out-neighbors."""
def ui_persistent_root_seeds() -> list[any] {
    seeds: list[any] = [];
    for n_any in [root -->] {
        seeds.append(n_any);
    }
    for m_any in [root <--] {
        seeds.append(m_any);
    }
    return seeds;
}


"""BFS from Jac persistent root across all edge types; return UI jids found."""
def ui_jids_reachable_from_persistent_root(ui_jids: set[str]) -> list[str] {
    return ui_jids_reachable_from_nodes(ui_persistent_root_seeds(), ui_jids);
}
