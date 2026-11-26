import os;
import json;
import time;
import uuid;
import tempfile;
import fcntl;
import urllib.request;
import urllib.parse;

glob ISSUER: str = "https://auth.openai.com",
     RESOURCE: str = "https://api.openai.com/v1";

def account_path -> str;

def read_accounts -> dict[str, any];

def write_accounts(data: dict[str, any]);

def account_lock -> any;

def request_json(
    url: str, fields: dict[str, str] | None = None, bearer: str = ""
) -> dict[str, any];

def selected_account -> dict[str, any];

def configured_account -> bool;

def host_identity -> str;

def token_record(
    tokens: dict[str, any], client_id: str, nonce: str, host: str, previous: dict[str, any]
) -> dict[str, any];

def save_account(record: dict[str, any]);

def access_token(account_key: str = "") -> str;

def logout_account -> str;

def select_account(key: str) -> bool;

def account_revision -> str;
