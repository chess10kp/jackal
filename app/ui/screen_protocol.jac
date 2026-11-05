"""In-process adapter from agent envelopes to the product shell graph.

The agent protocol owns envelopes and queues. Shell mutation belongs in the UI
layer so the protocol module does not import the screen type and create a
reverse dependency through the screen test annex.
"""

import from agent.protocol {
    Envelope,
    InProcessAdapter,
    dequeue,
}
import from ui.screen { ShellScreen }


"""Drive one envelope into the product TUI shell."""
def:pub drive_screen(
    adapter: InProcessAdapter, shell: ShellScreen, envelope: Envelope
) {
    kind = envelope.kind;
    if kind == "text_delta" {
        text = str(envelope.payload.get("text", ""));
        if text {
            adapter.stream_buf = adapter.stream_buf + text;
            shell.transcript.observed_revision += 1;
            if not shell.transcript.source_id {
                shell.transcript.source_id = envelope.turn_id;
            }
            adapter.busy = True;
        }
    } elif kind == "status" {
        phase = str(envelope.payload.get("phase", ""));
        if phase {
            shell.status.phase = phase;
            if phase == "streaming" or phase == "tool" {
                adapter.busy = True;
            } elif phase == "ready" or phase == "cancelled" {
                adapter.busy = False;
            }
        }
    } elif kind == "insert_text" {
        text = str(envelope.payload.get("text", ""));
        shell.prompt.draft = shell.prompt.draft + text;
    } elif kind == "tool_start" {
        tool = str(envelope.payload.get("tool", envelope.tool_id));
        adapter.last_tool = tool;
        shell.status.phase = "tool";
        adapter.busy = True;
    } elif kind == "tool_end" {
        shell.status.phase = "streaming";
        adapter.last_tool = "";
    } elif kind == "approval_request" {
        cid = envelope.correlation_id;
        if not cid {
            cid = str(envelope.payload.get("id", envelope.tool_id));
        }
        adapter.pending_approval_id = cid;
        shell.status.phase = "approval";
    } elif kind == "approval_decision" {
        adapter.pending_approval_id = "";
        approved = bool(envelope.payload.get("approved", False));
        shell.status.phase = "streaming" if approved else "ready";
    } elif kind == "turn_cancelled" or kind == "group_cancelled" {
        shell.status.phase = "cancelled";
        adapter.busy = False;
        adapter.pending_approval_id = "";
        if envelope.turn_id {
            adapter.cancelled_turns.add(envelope.turn_id);
        }
    } elif kind == "turn_end" {
        shell.status.phase = "ready";
        adapter.busy = False;
    } elif kind == "turn_start" {
        shell.status.phase = "streaming";
        adapter.stream_buf = "";
        adapter.busy = True;
        if envelope.turn_id {
            shell.transcript.source_id = envelope.turn_id;
        }
    }
}


"""Drain the adapter queue and apply each envelope to the shell."""
def:pub drain_and_drive(adapter: InProcessAdapter, shell: ShellScreen) -> int {
    count = 0;
    while True {
        env = dequeue(adapter.queue);
        if env is None {
            break;
        }
        drive_screen(adapter, shell, env);
        count += 1;
    }
    return count;
}
