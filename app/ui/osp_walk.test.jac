"""Tests for native OSP graph traversal helpers."""

test "overlapping seeds are processed once" {
    first = OspAny();
    second = OspAny();
    first ++> second;

    seeds: list[any] = [first, second, first];
    ui_ids: set[str] = set();
    ui_ids.add(jid(first));
    ui_ids.add(jid(second));

    assert ui_jids_reachable_from_nodes(seeds, ui_ids) == [
        jid(first),
        jid(second),
    ];
    neighbor_ids: set[str] = set();
    neighbor_ids.add(jid(second));
    assert ui_jids_reachable_from_nodes([first], neighbor_ids) == [
        jid(second),
    ];
}
