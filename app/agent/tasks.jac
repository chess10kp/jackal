import os;
import json;
import uuid;
import datetime;

glob TASKS_FILE: str = "tasks.json",
     _NO_TASKS_LINE: str = "No tasks. Use /tasks add <title> or create_task.";

def tasks_path(cwd: str) -> str;
def generate_task_id -> str;

def _now_iso -> str;
def _is_task(value: any) -> bool;
def load_tasks(cwd: str) -> list[dict[str, any]];
def save_tasks(cwd: str, tasks: list[dict[str, any]]) -> bool;
def clear_tasks(cwd: str) -> bool;
def add_task(cwd: str, title: str, description: str = "") -> dict[str, any];
def remove_task_by_index(cwd: str, index: int) -> dict[str, any] | None;
def remove_task_by_id(cwd: str, task_id: str) -> dict[str, any] | None;
def update_tasks(cwd: str, updates: list[dict[str, any]]) -> list[dict[str, any]];
def task_counts(tasks: list[dict[str, any]]) -> dict[str, int];
def format_task_line(task: dict[str, any]) -> str;
def format_tasks_list(tasks: list[dict[str, any]], title: str = "Tasks") -> str;
