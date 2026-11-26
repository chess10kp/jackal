import json;
import queue;
import threading;
import time;

def _node_alive(bridge: any) -> bool;

def _write_node(bridge: any, env: Envelope);
def _dispatch_inbound(bridge: any, env: Envelope);
def _reader_loop(bridge: any);

def _ensure_io(bridge: any);

def _start_reader(bridge: any);

def _stop_reader(bridge: any);
def _prepare_corr(bridge: any, correlation_id: str, expect_kind: str = "");

def _wait_corr(bridge: any, kind: str, correlation_id: str = "", timeout: float = 5.0) -> Envelope;

def _read_node(bridge: any, timeout: float = 5.0) -> Envelope;
def _read_node_until(
    bridge: any, kind: str, correlation_id: str = "", timeout: float = 5.0
) -> Envelope;
def _ui_queue(bridge: any) -> UiInteractionQueue;

def _ui_enqueue_from_env(bridge: any, env: Envelope);

def _ui_send_response(bridge: any, corr: str, status: str, value: any, reason: str = "") -> bool;
