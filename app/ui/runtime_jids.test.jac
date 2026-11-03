"""Reachability tests for ui_jids_reachable_from_persistent_root."""

import from ui.model {
    Prompt,
    TranscriptView,
    node_id,
}
import from ui.runtime {
    create_session,
    register_capability,
    dispose_session,
}
import from ui.bindings {
    subscribe,
}


test "detached ui_root is not reachable from persistent root" {
    handle = create_session();
    session = handle.session;
    assert session.ui_root is not None;
    reachable = ui_jids_reachable_from_persistent_root(session.tracked_node_ids);
    assert reachable == [];
    dispose_session(session);
}


test "registered capability node stays unreachable" {
    handle = create_session();
    session = handle.session;
    prompt = Prompt(key="p1");
    subscribe(
        session.bindings,
        "session.events",
        node_id(prompt),
        "TranscriptChanged",
    );
    register_capability(session, node_id(prompt), "input");
    assert ui_jids_reachable_from_persistent_root(session.tracked_node_ids) == [];
    dispose_session(session);
}


test "persistent root is included in its reachable jids" {
    root_id: str = jid(root);
    ui_ids: set[str] = set();
    ui_ids.add(root_id);
    assert ui_jids_reachable_from_persistent_root(ui_ids) == [root_id];
}
