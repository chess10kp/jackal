impl ui_persistent_root_seeds -> list[any] {
    seeds: list[any] = [];
    for n_any in [root -->] {
        seeds.append(n_any);
    }
    for m_any in [root <--] {
        seeds.append(m_any);
    }
    return seeds;
}

impl ui_jids_reachable_from_persistent_root(ui_jids: set[str]) -> list[str] {
    found: list[str] = [];
    root_jid: str = jid(root);
    if root_jid in ui_jids {
        found.append(root_jid);
    }
    for reachable_jid in ui_jids_reachable_from_nodes(ui_persistent_root_seeds(), ui_jids) {
        if reachable_jid not in found {
            found.append(reachable_jid);
        }
    }
    return found;
}
