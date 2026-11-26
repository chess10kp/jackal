import os;
import shutil;

def _path_abspath(p: str) -> str;

def _path_dirname(p: str) -> str;
def resolve_host_mjs(explicit: str = "") -> str;
def resolve_stub_echo(explicit: str = "") -> str;

def resolve_pi_greet(explicit: str = "") -> str;

def resolve_pi_ctx_probe(explicit: str = "") -> str;

def resolve_stub_commands(explicit: str = "") -> str;

def resolve_pi_gated(explicit: str = "") -> str;
def resolve_node_bin(explicit: str = "") -> str;

def envelope_to_dict(env: Envelope) -> dict[str, any];

def envelope_from_dict(data: dict[str, any]) -> Envelope;
