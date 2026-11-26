def redact_secret(secret: any, visible: int = 4) -> str;
def redact_credential(cred: any) -> dict[str, any] | None;
def validate_provider_entry(item: any) -> dict[str, any] | None;
def login_kind(auth_type: any) -> str;
def needs_oauth(auth_type: any) -> bool;
def validate_model_entry(item: any) -> dict[str, any] | None;
def filter_providers_by_query(providers: list[dict[str, any]], query: str) -> list[dict[str, any]];
def filter_models_by_query(
    models: list[dict[str, any]], query: str, provider_filter: str = ""
) -> list[dict[str, any]];
def format_provider_label(item: dict[str, any]) -> str;
def format_model_label(item: dict[str, any]) -> str;
