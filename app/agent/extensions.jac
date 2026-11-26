import json;
import os;
import time;
def _path_abspath(p: str) -> str;

def _path_dirname(p: str) -> str;

obj ExtensionDecl {
    has id: str = "",
        path: str = "",
        runtime: str = "node",
        activation: str = "sidecar",
        requires: list[str] = [];
}

obj ExtensionStatus {
    has phase: str = "idle",
        loaded: int = 0,
        total: int = 0,
        ready: bool = True,
        detail: str = "",
        label: str = "",
        t_interactive_s: float = 0.0,
        t_ext_ready_s: float = 0.0,
        compat_tier: str = "T0";
}

def decl_from_dict(raw: dict[str, any]) -> ExtensionDecl;
def decls_from_json(data: any) -> list[ExtensionDecl];
def load_extension_decls(cwd: str = "") -> list[ExtensionDecl];
def node_sidecar_decls(decls: list[ExtensionDecl]) -> list[ExtensionDecl];
def extensions_label(status: ExtensionStatus) -> str;
def resolve_decl_path(decl: ExtensionDecl, base_cwd: str) -> str;
