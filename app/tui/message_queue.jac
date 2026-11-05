"""Small typed event channel shared by TUI workers and the paint loop."""

import threading;

type Message = tuple[str, dict[str, any]];

obj:pub QueueEmpty(Exception) {}

obj:pub MessageQueue {
    has _items: list[Message] = [],
        _lock: threading.Lock = threading.Lock();

    def put(item: Message) -> None;
    def get_nowait() -> Message;
    def empty() -> bool;
    def qsize() -> int;
}

impl MessageQueue.put(item: Message) -> None {
    self._lock.acquire();
    self._items.append(item);
    self._lock.release();
}

impl MessageQueue.get_nowait() -> Message {
    self._lock.acquire();
    if not self._items {
        self._lock.release();
        raise QueueEmpty();
    }
    item: Message = self._items.pop(0);
    self._lock.release();
    return item;
}

impl MessageQueue.empty() -> bool {
    return self.qsize() == 0;
}

impl MessageQueue.qsize() -> int {
    self._lock.acquire();
    size = len(self._items);
    self._lock.release();
    return size;
}
