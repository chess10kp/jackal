import from json { dumps, loads }
import from sys { stderr, stdin, stdout }

def _build_expression(terms: list[list[any]], const: float) -> Expression;

def _run_batch(batch: dict[str, any]) -> dict[str, any];

with entry {
    for line in stdin {
        line = line.strip();
        if line == "" {
            continue;
        }
        try {
            batch = loads(line);
            out = _run_batch(batch);
        } except Exception as e {
            print("driver error:", e, file=stderr);
            out = {
                "schema_version": 1,
                "seed": -1,
                "ok": False,
                "error": "driver_exception",
                "values": {},
            };
        }
        stdout.write(dumps(out) + "\n");
    }
    stdout.flush();
}
