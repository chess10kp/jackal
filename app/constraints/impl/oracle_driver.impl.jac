impl _build_expression(terms: list[list[any]], const: float) -> Expression {
    acc: Expression = Expression(constant=const);
    for pair in terms {
        plist: list[any] = pair as list;
        vid: int = int(plist[0] as int);
        coef: float = plist[1] as float;
        acc = add_expressions(
            acc, Expression(terms=[Term(variable=Variable(id=vid), coefficient=coef)])
        );
    }
    return acc;
}

impl _run_batch(batch: dict[str, any]) -> dict[str, any] {
    version = batch.get("schema_version");
    if version != 1 {
        return {
            "schema_version": -1,
            "seed": -1,
            "ok": False,
            "error": "unknown_schema_version",
            "values": {},
        };
    }
    seed = batch.get("seed", 0);
    s = Solver();
    rel_map = {"eq": Relation.EQ, "le": Relation.LEQ, "ge": Relation.GEQ};
    ops_raw = batch.get("ops", []) as list;
    for op_any in ops_raw {
        op: dict[str, any] = op_any as dict;
        expr = _build_expression(op["terms"] as list, op["const"] as float);
        c = Constraint(
            expression=expr, relation=rel_map[op["rel"] as str], strength=StrengthTier.REQUIRED
        );
        r = s.add_constraint(c);
        if not r.ok {
            return {
                "schema_version": 1,
                "seed": seed,
                "ok": False,
                "error": r.error.value,
                "values": {},
            };
        }
    }
    snap = s.snapshot();
    vals: dict[str, float] = {};
    for vid in sorted(snap.values.keys()) {
        vals[str(vid)] = snap.values[vid];
    }
    return {"schema_version": 1, "seed": seed, "ok": True, "error": "ok", "values": vals};
}
