import copy;
def initial_auth_flow_state -> dict[str, any];
def _deep_copy(value: any) -> any;
def step_is_pending(state: dict[str, any]) -> bool;
def transition_auth_flow(
    current_state: dict[str, any], action: str, payload: dict[str, any] | None = None
) -> dict[str, any];
