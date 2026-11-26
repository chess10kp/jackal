impl ui_jids_reachable_from_nodes(seeds: list[any], ui_jids: set[str]) -> list[str] {
    found: list[str] = [];
    visited: set[str] = set();
    queue: list[Node] = [];
    for s_any in seeds {
        s: Node = s_any;
        sj: str = jid(s);
        if sj not in visited {
            visited.add(sj);
            queue.append(s);
        }
    }
    while queue {
        current: Node = queue.pop(0);
        current_jid: str = jid(current);
        if current_jid in ui_jids {
            found.append(current_jid);
        }
        for n_fwd in [current -->] {
            neighbor: Node = n_fwd;
            nj: str = jid(neighbor);
            if nj not in visited {
                visited.add(nj);
                queue.append(neighbor);
            }
        }
        for n_bwd in [current <--] {
            in_neighbor: Node = n_bwd;
            inj: str = jid(in_neighbor);
            if inj not in visited {
                visited.add(inj);
                queue.append(in_neighbor);
            }
        }
    }
    return found;
}
