"""Native graph-walk helpers over statically-typed OSP handles.

`jid` and `[n -->]`/`[n <--]` traversal lower natively, but only on
statically node/edge-typed operands — and only *declared* node
archetypes carry the `is_osp` native layout; the builtin `Node` stub
does not (upstream #10545). `OspAny` below is an empty node archetype
used purely as an opaque-handle marker: `osp_jid` and the edge-walk
ABI operate on the handle pointer only, so every node in the graph is
ABI-compatible with it. `root` has no native node yet, so
persistent-root seeding stays in ui.runtime_jids (server), which hands
raw node references in as `list[any]`.
"""

node OspAny {}


"""Bidirectional BFS over the OSP graph from seed node handles; return
the subset of `ui_jids` that is reachable."""
def:pub ui_jids_reachable_from_nodes(seeds: list[any], ui_jids: set[str]) -> list[str] {
    found: list[str] = [];
    visited: set[str] = set();
    queue: list[OspAny] = [];
    for s_any in seeds {
        s: OspAny = s_any;
        sj: str = jid(s);
        if sj not in visited {
            visited.add(sj);
            queue.append(s);
        }
    }
    while queue {
        current: OspAny = queue.pop(0);
        current_jid: str = jid(current);
        if current_jid in ui_jids {
            found.append(current_jid);
        }
        for n_fwd in [current -->] {
            neighbor: OspAny = n_fwd;
            nj: str = jid(neighbor);
            if nj not in visited {
                visited.add(nj);
                queue.append(neighbor);
            }
        }
        for n_bwd in [current <--] {
            in_neighbor: OspAny = n_bwd;
            inj: str = jid(in_neighbor);
            if inj not in visited {
                visited.add(inj);
                queue.append(in_neighbor);
            }
        }
    }
    return found;
}
