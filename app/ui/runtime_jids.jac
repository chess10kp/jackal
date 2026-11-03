"""Persistent-root reachability probe — server-only by design.

Uses the OSP `root` special var, `jid`, and `[n -->]`/`[<--]` edge traversal —
none of which lower natively. Split from ui.runtime_core because `root`
access is a placement blocker that marks the WHOLE module non-native
(PERSIST), which erased every signature type UiSession carries into native
units. This module stays soft-server; callers are server modules only —
native code must not call it across the boundary.
"""


"""BFS from Jac persistent root across all edge types; return UI jids found."""
def ui_jids_reachable_from_persistent_root(ui_jids: set[str]) -> list[str] {
    found: list[str] = [];
    visited: set[str] = set();
    queue: list[any] = [];
    queue.append(root);
    while queue {
        current = queue.pop(0);
        current_jid = jid(current);
        if current_jid in ui_jids {
            found.append(current_jid);
        }
        for neighbor in [current -->] {
            nj = jid(neighbor);
            if nj not in visited {
                visited.add(nj);
                queue.append(neighbor);
            }
        }
        for neighbor in [current <--] {
            nj = jid(neighbor);
            if nj not in visited {
                visited.add(nj);
                queue.append(neighbor);
            }
        }
    }
    return found;
}
