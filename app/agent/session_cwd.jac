"""Session working directory as a small scalar native boundary."""

glob:pub session_cwd: str = "";


def:pub get_session_cwd() -> str {
    return session_cwd;
}


def:pub set_session_cwd(cwd: str) -> None {
    session_cwd = cwd;
}
