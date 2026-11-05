"""Transcript mutation helpers for the interactive live shell demo."""

import from ui.transcript {
    TranscriptMessage,
    apply_transcript_revision,
}

import from ui.demo_live_shell_model { LiveShell }
import from tui.format { format_turn }


def _next_id(app: LiveShell) -> str {
    app.msg_n += 1;
    return "m" + str(app.msg_n);
}


def _commit_messages(app: LiveShell) {
    app.rev += 1;
    apply_transcript_revision(app.proj, app.rev, app.messages);
    app.dirty = True;
}


def:pub _push_turn(app: LiveShell, role: str, body: str) -> str {
    mid = _next_id(app);
    app.messages = app.messages + [
        TranscriptMessage(
            message_id=mid,
            content=format_turn(role, body),
            content_rev=1,
        )
    ];
    _commit_messages(app);
    return mid;
}


def:pub _rewrite_turn(app: LiveShell, message_id: str, role: str, body: str) {
    updated: list[TranscriptMessage] = [];
    for message in app.messages {
        if message.message_id == message_id {
            updated.append(
                TranscriptMessage(
                    message_id=message_id,
                    content=format_turn(role, body),
                    content_rev=message.content_rev + 1,
                )
            );
        } else {
            updated.append(message);
        }
    }
    app.messages = updated;
    _commit_messages(app);
}
