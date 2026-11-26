impl _jac_launcher(repo_root: str) -> str {
    workspace = os.path.join(repo_root, "jac");
    if os.path.isfile(workspace) and os.access(workspace, os.X_OK) {
        return workspace;
    }
    found = shutil.which("jac");
    return found or "jac";
}
