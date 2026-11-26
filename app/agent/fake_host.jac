import time;

def touch_bridge(bridge: any);
def apply_hello(bridge: any, hello: Envelope);
def ensure_host(bridge: any, host: FakePluginHost | None = None) -> str;
def register_fake_command(
    bridge: any, name: str, handler: any, description: str = "", extension_id: str = "fake.commands"
);

def register_fake_shortcut(
    bridge: any, key: str, handler: any, description: str = "", extension_id: str = "fake.shortcuts"
);
def register_fake_listener(bridge: any, event: str, handler: any);
def register_fake_transformer(bridge: any, fn: any, extension_id: str = "fake.xform");
def register_fake_provider(bridge: any, cfg: dict[str, any], extension_id: str = "fake.provider");
def register_fake_renderer(
    bridge: any, kind: str, renderer_type: str, fn: any, extension_id: str = "fake.renderer"
);

def fake_push_message(bridge: any, role: str, content: str);

def fake_push_entry(bridge: any, entry_type: str, data: dict[str, any]);

def set_fake_active_tools(bridge: any, names: list[str] | None);

def fake_session_name(bridge: any) -> str;

obj FakeUi {
    has notifications: list[str],
        ui_events: list[dict[str, any]];

    def notify(message: str, level: str = "info");

    def _record(method: str, args: list[str]);

    def set_status(owner: str, text: str);

    def set_widget(id: str, text: str);

    def set_footer(text: str);

    def set_title(text: str);

    def select(_title: str, _options: list[str]) -> any;

    def confirm(_message: str) -> bool;

    def input(_message: str, _default: str = "") -> str;
}
