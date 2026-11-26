import os;
def _login_provider_entries -> dict[str, any];
def _hydrate_auth_environment;

def _login_error(app: LiveShell, message: str);

def _cancel_login(app: LiveShell);

def _start_login_provider(app: LiveShell, provider_id: str);

def _complete_api_key_login(app: LiveShell, provider_id: str, key: str);
def _open_login_picker(app: LiveShell, provider_arg: str = "") -> str;
def _open_resume_picker(app: LiveShell) -> str;
def _task_picker_entries(cwd: str) -> dict[str, any];
def _checkpoint_picker_entries(cwd: str) -> dict[str, any];
def _open_skills_picker(app: LiveShell) -> str;
def _open_tasks_picker(app: LiveShell) -> str;
def _open_checkpoints_picker(app: LiveShell) -> str;
def _create_checkpoint_now(app: LiveShell, name: str) -> str;
def _restore_checkpoint(app: LiveShell, name: str) -> str;

def _tick_login(app: LiveShell);
