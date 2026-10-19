"""Solver module annex: tableau journal, primal simplex, dual simplex.

These bodies were previously separate modules (solver_journal.jac,
solver_simplex.jac, solver_dual.jac). They are folded into the
constraints.solver module so the mutable state type (`Solver`) can be named
directly: every former `s: any` parameter is now `s: Solver`, which is what
lets the whole module lower natively with no per-function demotions. Under
jac test a mixed native/Python graph segfaults at the seam (upstream jaclang
bug), so full-native lowering of this chain is a correctness requirement, not
just a performance one.
"""

# ---------------------------------------------------------------------------
# Tableau bookkeeping and exact rollback journal operations.
# ---------------------------------------------------------------------------

def _journal_expression_is_finite(s: Solver, e: Expression) -> bool {
    if not is_finite(e.constant) {
        return False;
    }
    for t in e.terms {
        if not is_finite(t.coefficient) {
            return False;
        }
    }
    return True;
}

def _journal_kind_of(s: Solver, symbol: int) -> SymbolKind {
    if symbol <= 0 {
        return SymbolKind.INVALID;
    }
    return s.kinds.get(symbol, SymbolKind.INVALID);
}

def _journal_begin(s: Solver) -> MutationJournal {
    return MutationJournal(
        id_tick_start=s.id_tick,
        infeasible_start=len(s.infeasible_rows),
    );
}

def _journal_witness_for_key(s: Solver, key: str) -> list[str] {
    out: list[str] = [];
    for hid in sorted(s.handle_keys.keys()) {
        if s.handle_keys[hid] == key and s.provenance.get(hid, "") != "" {
            out.append(s.provenance[hid]);
        }
    }
    return out;
}

def _journal_witness_extra(s: Solver, extra: str) -> list[str] {
    if extra == "" {
        return [];
    }
    return [extra];
}

def _journal_new_symbol(s: Solver, kind: SymbolKind) -> int {
    symbol = s.id_tick;
    s.id_tick += 1;
    s.kinds[symbol] = kind;
    return symbol;
}

def _journal_new_symbol_journaled(s: Solver, kind: SymbolKind, jnl: MutationJournal) -> int {
    symbol = _journal_new_symbol(s, kind);
    jnl.allocated_symbols.append(symbol);
    return symbol;
}

def _journal_get_var_symbol(s: Solver, v: Variable, jnl: MutationJournal | None = None) -> int {
    var_symbols: dict[int, int] = s.var_symbols;
    if v.id in var_symbols {
        return var_symbols[v.id];
    }
    symbol = _journal_new_symbol(s, SymbolKind.EXTERNAL);
    s.var_symbols[v.id] = symbol;
    if jnl is not None {
        jnl.new_var_ids.append(v.id);
        jnl.allocated_symbols.append(symbol);
    }
    return symbol;
}

def _journal_insert_row(s: Solver, symbol: int, row: Row, jnl: MutationJournal) -> None {
    if (
        symbol not in jnl.inserted_rows
        and symbol not in jnl.row_snapshots
    ) {
        jnl.inserted_rows.append(symbol);
    }
    s.rows[symbol] = row;
}

def _journal_touch_row(s: Solver, symbol: int, jnl: MutationJournal) -> None {
    rows: dict[int, Row] = s.rows;
    if (
        symbol in rows
        and symbol not in jnl.row_snapshots
        and symbol not in jnl.inserted_rows
    ) {
        jnl.row_snapshots[symbol] = rows[symbol].clone();
    }
}

def _journal_touch_objective(s: Solver, jnl: MutationJournal) -> None {
    if jnl.objective_snapshot is None {
        jnl.objective_snapshot = s.objective.clone();
    }
}

def _journal_pop_row(s: Solver, symbol: int, jnl: MutationJournal) -> Row {
    _journal_touch_row(s, symbol, jnl);
    return s.rows.pop(symbol);
}

def _journal_rollback(s: Solver, jnl: MutationJournal) -> None {
    rows: dict[int, Row] = s.rows;
    # 1. Drop rows created during the operation.
    for symbol in reversed(jnl.inserted_rows) {
        if symbol in rows {
            rows.pop(symbol);
        }
    }
    # 2. Restore pre-existing rows to pre-mutation state; re-inserts
    #    rows optimize() may have moved or removed.
    for symbol in sorted(jnl.row_snapshots.keys()) {
        rows[symbol] = jnl.row_snapshots[symbol].clone();
    }
    # 3. Restore the objective row.
    if jnl.objective_snapshot is not None {
        s.objective = jnl.objective_snapshot.clone();
    }
    # 4. Unregister external variables introduced here.
    for vid in reversed(jnl.new_var_ids) {
        s.var_symbols.pop(vid);
    }
    # 5. Release symbols and rewind the id counter.
    for symbol in reversed(jnl.allocated_symbols) {
        s.kinds.pop(symbol);
    }
    s.id_tick = jnl.id_tick_start;
    # 6. Drop worklist entries recorded during the failed operation.
    del s.infeasible_rows[jnl.infeasible_start:];
}

# ---------------------------------------------------------------------------
# Constraint insertion and primal simplex algorithm.
# ---------------------------------------------------------------------------

def _solver_add_core(s: Solver, c: Constraint, tag: Tag, jnl: MutationJournal) -> SolveResult {
    row = _solver_create_row(s, c, tag, jnl);
    subject = _solver_choose_subject(s, row, tag);

    # No valid entering subject: an all-dummy row is redundant when its
    # constant is zero (the dummy marker may enter the basis) and
    # unsatisfiable otherwise (kiwi addConstraint).
    if (
        _journal_kind_of(s, subject) == SymbolKind.INVALID
        and _solver_all_dummies(s, row)
    ) {
        if not near_zero(row.constant) {
            return SolveResult(
                ok=False,
                error=SolveError.UNSATISFIABLE,
                message="required system inconsistent",
            );
        }
        subject = tag.marker;
    }

    if _journal_kind_of(s, subject) == SymbolKind.INVALID {
        if not _solver_add_with_artificial_variable(s, row, jnl) {
            return SolveResult(
                ok=False,
                error=SolveError.UNSATISFIABLE,
                message="artificial variable could not reach zero",
            );
        }
    } else {
        row.solve_for(subject);
        _solver_substitute(s, subject, row, jnl);
        _journal_insert_row(s, subject, row, jnl);
    }

    # Optimize after every mutation. The target is lexicographic, so
    # higher tiers are exhausted before lower tiers are considered.
    return _solver_optimize_cost(s, jnl);
}

def _solver_create_row(s: Solver, c: Constraint, tag: Tag, jnl: MutationJournal) -> Row {
    row = Row(constant=c.expression.constant);
    # Substitute already-basic variables from the current tableau.
    for t in c.expression.terms {
        if not near_zero(t.coefficient) {
            symbol = _journal_get_var_symbol(s, t.variable, jnl);
            basic = s.rows.get(symbol);
            if basic is not None {
                row.insert_row(basic, t.coefficient);
            } else {
                row.insert_symbol(symbol, t.coefficient);
            }
        }
    }
    if c.relation == Relation.LEQ or c.relation == Relation.GEQ {
        coeff = 1.0 if c.relation == Relation.LEQ else -1.0;
        slack = _journal_new_symbol_journaled(s, SymbolKind.SLACK, jnl);
        tag.marker = slack;
        row.insert_symbol(slack, coeff);
        if c.strength == StrengthTier.REQUIRED {
            # A required inequality has only its non-negative slack.
            tag.other = 0;
        } else {
            # LEQ violation is positive expression, hence -error; GEQ
            # violation is negative expression, hence +error.
            error = _journal_new_symbol_journaled(s, SymbolKind.ERROR, jnl);
            tag.other = error;
            row.insert_symbol(error, -coeff);
            _solver_add_objective(s, error, strength_weight(c.strength), jnl);
        }
    } else {
        if c.strength == StrengthTier.REQUIRED {
            # Required equality: a dummy marker keeps the basis restricted.
            dummy = _journal_new_symbol_journaled(s, SymbolKind.DUMMY, jnl);
            tag.marker = dummy;
            row.insert_symbol(dummy);
        } else {
            # A soft equality needs two non-negative error
            # directions: v == eplus - eminus, i.e. v - eplus +
            # eminus = 0 (kiwi OP_EQ soft case). The marker keeps a
            # NEGATIVE coefficient so chooseSubject can pick it as
            # pivot subject when no external symbol is available.
            plus = _journal_new_symbol_journaled(s, SymbolKind.ERROR, jnl);
            minus = _journal_new_symbol_journaled(s, SymbolKind.ERROR, jnl);
            tag.marker = plus;
            tag.other = minus;
            row.insert_symbol(plus, -1.0);
            row.insert_symbol(minus, 1.0);
            weight = strength_weight(c.strength);
            _solver_add_objective(s, plus, weight, jnl);
            _solver_add_objective(s, minus, weight, jnl);
        }
    }
    if row.constant < 0.0 {
        row.reverse_sign();
    }
    return row;
}

def _solver_choose_subject(s: Solver, row: Row, tag: Tag) -> int {
    for symbol in sorted(row.cells.keys()) {
        if _journal_kind_of(s, symbol) == SymbolKind.EXTERNAL {
            return symbol;
        }
    }
    for candidate in [tag.marker, tag.other] {
        kind = _journal_kind_of(s, candidate);
        if (
            (kind == SymbolKind.SLACK or kind == SymbolKind.ERROR)
            and row.coefficient_for(candidate) < 0.0
        ) {
            return candidate;
        }
    }
    return 0;
}

def _solver_all_dummies(s: Solver, row: Row) -> bool {
    for symbol in sorted(row.cells.keys()) {
        if _journal_kind_of(s, symbol) != SymbolKind.DUMMY {
            return False;
        }
    }
    return True;
}

def _solver_any_pivotable_symbol(s: Solver, row: Row) -> int {
    for symbol in sorted(row.cells.keys()) {
        kind = _journal_kind_of(s, symbol);
        if kind == SymbolKind.SLACK or kind == SymbolKind.ERROR {
            return symbol;
        }
    }
    return 0;
}

def _solver_add_with_artificial_variable(s: Solver, row: Row, jnl: MutationJournal) -> bool {
    art = _journal_new_symbol_journaled(s, SymbolKind.SLACK, jnl);
    art_row = Row(constant=row.constant);
    art_row.cells = dict(row.cells);
    _journal_insert_row(s, art, art_row, jnl);

    # Artificial cost row; kept in sync by every pivot below
    # (kiwi m_artificial, substituted inside substitute()).
    artificial = Row(constant=row.constant);
    artificial.cells = dict(row.cells);
    _solver_optimize_toward(s, artificial, jnl, artificial);

    success = near_zero(artificial.constant);

    if art in s.rows {
        pivot_row = _journal_pop_row(s, art, jnl);
        if len(pivot_row.cells) > 0 {
            entering = _solver_any_pivotable_symbol(s, pivot_row);
            if entering == 0 {
                return False;
            }
            pivot_row.insert_symbol(art, -1.0);
            pivot_row.solve_for(entering);
            _solver_substitute(s, entering, pivot_row, jnl, artificial);
            _journal_insert_row(s, entering, pivot_row, jnl);
        }
    }

    for symbol in sorted(s.rows.keys()) {
        _journal_touch_row(s, symbol, jnl);
        s.rows[symbol].remove_symbol(art);
    }
    _journal_touch_objective(s, jnl);
    s.objective.remove_symbol(art);
    return success;
}

def _solver_substitute(s: Solver,
    symbol: int,
    row: Row,
    jnl: MutationJournal,
    extra: Row | None = None,
) -> None {
    for row_symbol in sorted(s.rows.keys()) {
        _journal_touch_row(s, row_symbol, jnl);
        r = s.rows[row_symbol];
        r.substitute(symbol, row);
        # Negative non-external constants would be tracked for
        # dualOptimize from M3 onward (kiwi m_infeasible_rows).
    }
    _journal_touch_objective(s, jnl);
    s.objective.substitute(symbol, row);
    # The artificial cost row participates in its own pivots
    # (kiwi substitutes into m_artificial when present).
    if extra is not None {
        extra.substitute(symbol, row);
    }
    # Track rows driven out of feasibility so a later suggestion's
    # dualOptimize can repair them (kiwi m_infeasible_rows).
    for row_symbol in sorted(s.rows.keys()) {
        if (
            _journal_kind_of(s, row_symbol) != SymbolKind.EXTERNAL
            and s.rows[row_symbol].constant < 0.0
            and s.infeasible_rows.count(row_symbol) == 0
        ) {
            s.infeasible_rows.append(row_symbol);
        }
    }
}

def _solver_add_objective(s: Solver, 
    symbol: int,
    weight: LexWeight,
    jnl: MutationJournal,
) -> None {
    if lex_is_zero(weight) {
        return;
    }
    _journal_touch_objective(s, jnl);
    s.objective.insert_symbol(symbol, weight);
    if s.rows.get(symbol) is not None {
        s.objective.substitute(symbol, s.rows[symbol]);
    }
}

def _solver_rebuild_admitting(s: Solver, candidate: Constraint) -> Solver | None {
    stored: list[StoredConstraint] = list(s.history);
    stored.append(StoredConstraint(
        expression=candidate.expression,
        relation=candidate.relation,
        strength=candidate.strength,
        content_key=constraint_key(candidate),
    ));

    orders: list[list[StoredConstraint]] = [
        stored,
        [_solver_terms_reversed(s, st) for st in stored],
        list(reversed(stored)),
        [_solver_terms_reversed(s, st) for st in reversed(stored)],
    ];

    for order in orders {
        attempt = _solver_replay_all(s, order);
        if attempt is not None {
            return attempt;
        }
    }
    return None;
}

def _solver_terms_reversed(s: Solver, st: StoredConstraint) -> StoredConstraint {
    terms_rev = [];
    for t in st.expression.terms {
        terms_rev.append(Term(
            variable=Variable(id=t.variable.id),
            coefficient=t.coefficient,
        ));
    }
    return StoredConstraint(
        expression=Expression(terms=terms_rev, constant=st.expression.constant),
        relation=st.relation,
        strength=st.strength,
        provenance=st.provenance,
        content_key=st.content_key,
    );
}

def _solver_replay_all(s: Solver, order: list[StoredConstraint]) -> Solver | None {
    # Replay on a scratch tableau so `self` stays untouched unless the
    # caller adopts the result.
    scratch = _new_solver();
    tags: dict[str, Tag] = {};
    for st in order {
        c = Constraint(
            expression=st.expression,
            relation=st.relation,
            strength=st.strength,
        );
        jnl = _journal_begin(scratch);
        tag = Tag();
        res = _solver_add_core(scratch, c, tag, jnl);
        if not res.ok {
            return None;
        }
        key = constraint_key(c);
        tags[key] = tag;
    }
    scratch.cns = tags;
    # Preserve the complete accepted set so a future rebuild after this
    # adoption does not silently forget constraints.
    scratch.history = list(order);
    return scratch;
}

def _solver_pivot(s: Solver, 
    entering: int,
    leaving: int,
    jnl: MutationJournal,
    extra: Row | None = None,
    reinsert: bool = True,
) -> None {
    row = _journal_pop_row(s, leaving, jnl);
    row.solve_for_symbols(leaving, entering);
    _solver_substitute(s, entering, row, jnl, extra);
    if reinsert {
        _journal_insert_row(s, entering, row, jnl);
    }
}

def _solver_optimize_cost(s: Solver, jnl: MutationJournal) -> SolveResult {
    while True {
        entering = _solver_get_entering_cost_symbol(s);
        if entering == 0 {
            return SolveResult(ok=True);
        }
        leaving = _solver_get_leaving_row(s, entering);
        if leaving == 0 {
            return SolveResult(
                ok=False,
                error=SolveError.INTERNAL_INVARIANT,
                message="lexicographic objective unbounded",
            );
        }
        _solver_pivot(s, entering, leaving, jnl);
    }
}

def _solver_optimize_toward(s: Solver, 
    target: Row,
    jnl: MutationJournal,
    extra: Row | None = None,
) -> SolveResult {
    while True {
        entering = _solver_get_entering_symbol(s, target);
        if entering == 0 {
            return SolveResult(ok=True);
        }
        leaving = _solver_get_leaving_row(s, entering);
        if leaving == 0 {
            return SolveResult(
                ok=False,
                error=SolveError.INTERNAL_INVARIANT,
                message="objective unbounded",
            );
        }
        _solver_pivot(s, entering, leaving, jnl, extra);
    }
}

def _solver_get_entering_symbol(s: Solver, objective: Row) -> int {
    for symbol in sorted(objective.cells.keys()) {
        if (
            _journal_kind_of(s, symbol) != SymbolKind.DUMMY
            and objective.cells[symbol] < 0.0
        ) {
            return symbol;
        }
    }
    return 0;
}

def _solver_get_entering_cost_symbol(s: Solver) -> int {
    for symbol in sorted(s.objective.cells.keys()) {
        if (
            _journal_kind_of(s, symbol) != SymbolKind.DUMMY
            and lex_is_negative(s.objective.cells[symbol])
        ) {
            return symbol;
        }
    }
    return 0;
}

def _solver_get_leaving_row(s: Solver, entering: int) -> int {
    ratio = 1e308;
    found = 0;
    for symbol in sorted(s.rows.keys()) {
        if _journal_kind_of(s, symbol) == SymbolKind.EXTERNAL {
            continue;
        }
        temp = s.rows[symbol].coefficient_for(entering);
        if temp < 0.0 {
            temp_ratio = -s.rows[symbol].constant / temp;
            if temp_ratio < ratio {
                ratio = temp_ratio;
                found = symbol;
            }
        }
    }
    return found;
}

# ---------------------------------------------------------------------------
# Constraint removal and dual simplex algorithm.
# ---------------------------------------------------------------------------

def _solver_remove_core(s: Solver, tag: Tag, strength: StrengthTier, jnl: MutationJournal) -> SolveResult {
    # Remove the error effects from the objective BEFORE pivoting, or
    # substitutions into the objective would double-count them.
    _solver_remove_constraint_effects(s, tag, strength, jnl);
    marker = tag.marker;
    rows: dict[int, Row] = s.rows;
    if marker in rows {
        # Marker is basic: simply drop the row.
        _journal_pop_row(s, marker, jnl);
    } else {
        leaving = _solver_get_marker_leaving_row(s, marker);
        if leaving == 0 {
            return SolveResult(
                ok=False,
                error=SolveError.INTERNAL_INVARIANT,
                message="failed to find leaving row",
            );
        }
        _solver_pivot(s, marker, leaving, jnl, reinsert=False);
    }
    # Optimize so the solver stays consistent after removal.
    return _solver_optimize_cost(s, jnl);
}

def _solver_remove_constraint_effects(s: Solver, 
    tag: Tag,
    strength: StrengthTier,
    jnl: MutationJournal,
) -> None {
    weight = strength_weight(strength);
    if lex_is_zero(weight) {
        return;
    }
    if _journal_kind_of(s, tag.marker) == SymbolKind.ERROR {
        _solver_remove_marker_effects(s, tag.marker, weight, jnl);
    }
    if _journal_kind_of(s, tag.other) == SymbolKind.ERROR {
        _solver_remove_marker_effects(s, tag.other, weight, jnl);
    }
}

def _solver_remove_marker_effects(s: Solver, 
    marker: int,
    weight: LexWeight,
    jnl: MutationJournal,
) -> None {
    _journal_touch_objective(s, jnl);
    row = s.rows.get(marker);
    if row is not None {
        s.objective.insert_row(row, lex_neg(weight));
    } else {
        s.objective.insert_symbol(marker, lex_neg(weight));
    }
}

def _solver_get_marker_leaving_row(s: Solver, marker: int) -> int {
    ratio1 = 1e308;
    ratio2 = 1e308;
    first = 0;
    second = 0;
    third = 0;
    for symbol in sorted(s.rows.keys()) {
        coeff = s.rows[symbol].coefficient_for(marker);
        if near_zero(coeff) {
            continue;
        }
        if _journal_kind_of(s, symbol) == SymbolKind.EXTERNAL {
            third = symbol;
        } elif coeff < 0.0 {
            r = -s.rows[symbol].constant / coeff;
            if r < ratio1 {
                ratio1 = r;
                first = symbol;
            }
        } else {
            r = s.rows[symbol].constant / coeff;
            if r < ratio2 {
                ratio2 = r;
                second = symbol;
            }
        }
    }
    if first != 0 {
        return first;
    }
    if second != 0 {
        return second;
    }
    return third;
}

def _solver_dual_optimize(s: Solver, jnl: MutationJournal) -> SolveResult {
    while len(s.infeasible_rows) > 0 {
        leaving = s.infeasible_rows.pop();
        row = s.rows.get(leaving);
        if (
            row is None
            or near_zero(row.constant)
            or row.constant >= 0.0
        ) {
            continue;
        }
        entering = _solver_get_dual_entering_symbol(s, row);
        if entering == 0 {
            return SolveResult(
                ok=False,
                error=SolveError.INTERNAL_INVARIANT,
                message="dual optimize failed",
            );
        }
        _solver_pivot(s, entering, leaving, jnl);
    }
    return SolveResult(ok=True);
}

def _solver_get_dual_entering_symbol(s: Solver, row: Row) -> int {
    entering = 0;
    best_coeff = 0.0;
    for symbol in sorted(row.cells.keys()) {
        cell = row.cells[symbol];
        if cell <= 0.0 or _journal_kind_of(s, symbol) == SymbolKind.DUMMY {
            continue;
        }
        if entering == 0 or _solver_dual_ratio_less(s, 
            _solver_objective_weight(s, symbol),
            cell,
            _solver_objective_weight(s, entering),
            best_coeff,
        ) {
            entering = symbol;
            best_coeff = cell;
        }
    }
    return entering;
}

def _solver_objective_weight(s: Solver, symbol: int) -> LexWeight {
    return s.objective.cells.get(symbol, lex_zero());
}

def _solver_dual_ratio_less(s: Solver, 
    w1: LexWeight,
    c1: float,
    w2: LexWeight,
    c2: float,
) -> bool {
    return lex_compare(lex_scale(w1, c2), lex_scale(w2, c1)) < 0;
}

def _solver_apply_suggestion(s: Solver, 
    info: EditInfo,
    delta: float,
    jnl: MutationJournal,
) -> None {
    marker = s.cns[info.key].marker;
    other = s.cns[info.key].other;
    row = s.rows.get(marker);
    if row is not None {
        _journal_touch_row(s, marker, jnl);
        if row.add(-delta) < 0.0 {
            s.infeasible_rows.append(marker);
        }
        return;
    }
    row = s.rows.get(other);
    if row is not None {
        _journal_touch_row(s, other, jnl);
        if row.add(delta) < 0.0 {
            s.infeasible_rows.append(other);
        }
        return;
    }
    for symbol in sorted(s.rows.keys()) {
        r = s.rows[symbol];
        coeff = r.coefficient_for(marker);
        if near_zero(coeff) {
            continue;
        }
        _journal_touch_row(s, symbol, jnl);
        if r.add(delta * coeff) < 0.0 {
            if _journal_kind_of(s, symbol) != SymbolKind.EXTERNAL {
                s.infeasible_rows.append(symbol);
            }
        }
    }
}

def _solver_adopt(s: Solver, bundle: Solver) -> None {
    s.rows = bundle.rows;
    s.kinds = bundle.kinds;
    s.var_symbols = bundle.var_symbols;
    s.objective = bundle.objective;
    s.id_tick = bundle.id_tick;
    s.cns = bundle.cns;
    # Stale worklist entries would reference old-symbol ids that now
    # denote different rows in the adopted tableau.
    s.infeasible_rows = bundle.infeasible_rows;
}
