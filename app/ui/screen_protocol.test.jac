"""Agent envelope to UI shell adapter acceptance tests."""

import from agent.protocol {
    create_adapter,
    enqueue,
    make_envelope,
}
import from ui.runtime { create_session, dispose_session }
import from ui.screen { build_main_shell }
import from ui.screen_protocol { drain_and_drive }


test "agent envelopes drive shell status tool approval and cancel" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    adapter = create_adapter("drv");
    enqueue(adapter.queue, make_envelope(kind="turn_start", turn_id="t1"));
    enqueue(
        adapter.queue,
        make_envelope(
            kind="text_delta",
            payload={"text": "hi"},
            turn_id="t1",
            correlation_id="c",
        ),
    );
    enqueue(
        adapter.queue,
        make_envelope(
            kind="tool_start",
            tool_id="bash",
            payload={"tool": "bash"},
            turn_id="t1",
        ),
    );
    enqueue(
        adapter.queue,
        make_envelope(
            kind="approval_request",
            correlation_id="ap-1",
            tool_id="bash",
            turn_id="t1",
        ),
    );
    n = drain_and_drive(adapter, shell);
    assert n == 4;
    assert adapter.stream_buf == "hi";
    assert adapter.last_tool == "bash";
    assert adapter.pending_approval_id == "ap-1";
    assert shell.status.phase == "approval";
    enqueue(
        adapter.queue,
        make_envelope(
            kind="turn_cancelled",
            turn_id="t1",
            correlation_id="t1",
        ),
    );
    drain_and_drive(adapter, shell);
    assert shell.status.phase == "cancelled";
    assert adapter.busy == False;
    dispose_session(session);
}
