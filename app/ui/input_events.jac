"""Host-event value objects shared by the input decoder and normalizer."""


glob:pub ESC = "\x1b";
glob:pub BRACKETED_PASTE_START = "\x1b[200~";
glob:pub BRACKETED_PASTE_END = "\x1b[201~";


obj:pub HostEvent {
    has kind: str = "";
}


obj:pub TextEvent(HostEvent) {
    has text: str = "";

    def init(text: str = "") {
        self.kind = "text";
        self.text = text;
    }
}


obj:pub KeyEvent(HostEvent) {
    has key: str = "";

    def init(key: str = "") {
        self.kind = "key";
        self.key = key;
    }
}


obj:pub PasteEvent(HostEvent) {
    has text: str = "";

    def init(text: str = "") {
        self.kind = "paste";
        self.text = text;
    }
}


obj:pub ResizeEvent(HostEvent) {
    has width: int = 0,
        height: int = 0;

    def init(width: int = 0, height: int = 0) {
        self.kind = "resize";
        self.width = width;
        self.height = height;
    }
}


obj:pub MouseEvent(HostEvent) {
    has button: int = 0,
        x: int = 0,
        y: int = 0,
        pressed: bool = False,
        motion: bool = False;

    def init(
        button: int = 0,
        x: int = 0,
        y: int = 0,
        pressed: bool = False,
        motion: bool = False,
    ) {
        self.kind = "mouse";
        self.button = button;
        self.x = x;
        self.y = y;
        self.pressed = pressed;
        self.motion = motion;
    }
}


obj:pub StreamChunkEvent(HostEvent) {
    has text: str = "";

    def init(text: str = "") {
        self.kind = "stream";
        self.text = text;
    }
}

obj:pub EofEvent(HostEvent) {
    def init() {
        self.kind = "eof";
    }
}


obj:pub InterruptEvent(HostEvent) {
    def init() {
        self.kind = "interrupt";
    }
}
