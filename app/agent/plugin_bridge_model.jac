"""Shared, statically typed plugin bridge state."""

import subprocess;
import threading;
import from .fake_host_types { FakePluginHost }
import from .interactions { UiInteractionQueue }
import from .protocol { Envelope }

obj:pub BridgeWaiter {
    has event: threading.Event,
        expect: str,
        env: Envelope | None = None,
        ui_lease_start: float = 0.0;
}

obj:pub PluginBridge {
    has session_id: str = "",
        host: FakePluginHost | None = None,
        host_kind: str = "",
        proc: subprocess.Popen | None = None,
        stdin_fd: int = -1,
        stdout_fd: int = -1,
        reader_buffer: bytes = b"",
        node_bin: str = "node",
        host_mjs: str = "",
        next_corr: int = 1,
        inbox: list[Envelope] = [],
        last_active: float = 0.0,
        status_phase: str = "idle",
        idle_timeout_s: float = 300.0,
        pending: dict[str, BridgeWaiter] = {},
        reader_stop: threading.Event | None = None,
        reader_thread: threading.Thread | None = None,
        write_lock: threading.Lock | None = None,
        restart_used: bool = False,
        host_caps: list[str] = [],
        compat_tier: str = "T0",
        hello_payload: dict[str, any] = {},
        commands: dict[str, dict[str, any]] = {},
        md_transformers: list[dict[str, any]] = [],
        providers: dict[str, dict[str, any]] = {},
        ui_q: UiInteractionQueue | None = None,
        interactive_ui: bool = False,
        traffic_messages: list[dict[str, any]] = [],
        traffic_entries: list[dict[str, any]] = [],
        session_name: str = "",
        shortcuts: dict[str, dict[str, any]] = {},
        labels: dict[str, dict[str, any]] = {},
        pending_model: str = "",
        pending_thinking_level: str = "";

}
