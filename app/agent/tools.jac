import os;
import subprocess;
import tempfile;
import shutil;
import fnmatch;
import re;

glob MAX_TOOL_OUTPUT: int = MAX_TOOL_RESULT,
     READ_LINE_CAP: int = 2_000,
     SANDBOX_ROOT_ENV: str = "JACKAL_SANDBOX_ROOT",
     user_bash_fire: Callable[[str, str], None] | None = None;
def _normalize_abs(path: str) -> str;
def _sandbox_root -> str;
def resolve_path(path: str) -> str;

sem resolve_path = "Resolve a possibly-relative path to an absolute one. Internal helper.";
sem resolve_path.path = "Filesystem path, relative or absolute.";

def read_file(path: str) -> str;

sem read_file = "Read a text file and return its contents. Use this before editing a file you have not seen this session.";
sem read_file.path = "Filesystem path to read, relative to the project root.";

def write_file(path: str, content: str) -> str;

sem write_file = "Create or completely overwrite a file with the given content. Prefer edit_file for small changes to existing files.";
sem write_file.path = "Filesystem path to write.";
sem write_file.content = "Full file content to write.";

def edit_file(path: str, old_text: str, new_text: str) -> str;

sem edit_file = "Replace an exact, unique snippet in a file. old_text must match the file byte-for-byte and appear exactly once; on failure read the file again and retry with a wider or corrected snippet.";
sem edit_file.path = "Filesystem path of the file to edit.";
sem edit_file.old_text = "Exact existing text to replace, including indentation.";
sem edit_file.new_text = "Replacement text.";

def list_dir(path: str) -> str;

sem list_dir = "List immediate entries of a directory (dotfiles hidden, directories suffixed with /). Use for exploration before reading files.";
sem list_dir.path = "Directory path to list.";

def run_command(cmd: str, timeout_secs: int = 120) -> str;

sem run_command = "Run a shell command in the project root and return exit code plus combined stdout/stderr. Use for builds, tests, git, and inspection commands.";
sem run_command.cmd = "The shell command line to execute.";
sem run_command.timeout_secs = "Seconds before the command is killed (default 120).";

glob JAC_CHILD_ENV_DROP: list[str] = ["JAC_HANDOFF"];
def _jac_child_env -> dict[str, str];
def _run_jac_cli(args: list[str], timeout_secs: int = 120) -> str;
def jac_check(path: str = ".") -> str;

sem jac_check = "Check Jac files for syntax/type errors with the Jac toolchain. Read-only; run this after editing .jac files.";
sem jac_check.path = "File or directory to check (default: project root).";
def jac_format(path: str = ".") -> str;

sem jac_format = "Format Jac files in place with the Jac formatter. Modifies files on disk.";
sem jac_format.path = "File or directory to format (default: project root).";

def _skip_walk_dir(name: str) -> bool;

def _search_limit(limit: int) -> int;

def file_glob(pattern: str, base_dir: str = ".", max_results: int = MAX_SEARCH_RESULTS) -> str;

sem file_glob = "Find files matching a pattern under the project root. Hidden directories, node_modules, .jac, and __pycache__ are skipped.";
sem file_glob.pattern = "Shell-style file pattern such as **/*.jac or *.md.";
sem file_glob.base_dir = "Directory to search, relative to the project root (default .).";
sem file_glob.max_results = "Maximum results to return, capped at 100.";

def content_grep(
    pattern: str, base_dir: str = ".", regex: bool = False, max_results: int = MAX_SEARCH_RESULTS
) -> str;

sem content_grep = "Search file contents for a literal or regular-expression pattern under the project root. Hidden directories, node_modules, .jac, and __pycache__ are skipped.";
sem content_grep.pattern = "Text or regular expression to search for.";
sem content_grep.base_dir = "Directory to search, relative to the project root (default .).";
sem content_grep.regex = "Use regular-expression matching instead of literal matching (default false).";
sem content_grep.max_results = "Maximum matches to return, capped at 100.";

def _read_file_tool(args: dict[str, any]) -> str;

def _write_file_tool(args: dict[str, any]) -> str;

def _edit_file_tool(args: dict[str, any]) -> str;

def _list_dir_tool(args: dict[str, any]) -> str;

def _run_command_tool(args: dict[str, any]) -> str;

def _jac_check_tool(args: dict[str, any]) -> str;

def _jac_format_tool(args: dict[str, any]) -> str;

def _glob_tool(args: dict[str, any]) -> str;

def _grep_tool(args: dict[str, any]) -> str;
def tool_specs -> list[ToolSpec];
def default_registry -> ToolRegistry;
