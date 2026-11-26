import os;
import time;
import json;
import urllib.request;

glob _CATALOG_REFRESHING: dict[str, bool] = {};

glob CATALOG_TTL_MS: int = 60_000;

glob MAX_CATALOG_MODELS: int = 256;

glob _CATALOG_CACHE: dict[str, dict[str, any]] = {};

def _now_ms -> int;
def _ttl_ms -> int;
def _parse_models_payload(payload: any) -> list[str];
def _entry_is_fresh(cached: dict[str, any] | None, now_ms: int, ttl_ms: int) -> bool;
def _merge_catalog_result(
    provider: str, fetched: list[str], fallback: list[str], now_ms: int
) -> list[str];
def _static_models(route: dict[str, any] | None) -> list[str];
def _is_local_route(route: dict[str, any] | None) -> bool;
def _fetch_route_models(route: dict[str, any]) -> list[str];
def catalog_models(provider: str) -> list[str];
def warm_model_catalog;
def refresh_model_catalog -> dict[str, int];

def _refresh_one(provider: str);

def _schedule_catalog_refresh(provider: str);

def invalidate_openai_catalog;

def fetch_account_models -> list[str];

glob _OPENAI_LABELS: dict[str, str] = {};
def account_model_label(model: str) -> str;
