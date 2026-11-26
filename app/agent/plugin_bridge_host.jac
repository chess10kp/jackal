import os;
import subprocess;
import time;

def _emit_host_status(bridge: any, phase: str, detail: str = "");

def _node_alive(bridge: any) -> bool;

def host_status(bridge: any) -> str;
def maybe_reap_idle(bridge: any, idle_timeout_s: float = -1.0, now: float = -1.0) -> bool;

def ensure_node_host(
    bridge: any, host_mjs: str = "", node_bin: str = "", timeout: float = 5.0
) -> str;
def maybe_restart_host(bridge: any, timeout: float = 5.0) -> str;

def dispose_bridge(bridge: any);
