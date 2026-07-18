// Policy evaluation — scope matching + condition evaluation.
// Reference: cedar-policy-core/src/evaluator.rs

///|
/// Evaluate a single condition (body of When or Unless).
/// Returns Value(Bool(true)) if condition passes (When is true, Unless is false).
/// Returns Value(Bool(false)) if condition fails (When is false, Unless is true).
/// Returns Residual(expr) if the condition body could not be fully reduced.
fn[S : EntityStore] eval_single_condition(
  cond : @ast.Condition,
  req : Request,
  store : S,
) -> @ast.PartialValue raise EvalError {
  match eval_expr(cond.body, req, store) {
    @ast.PartialValue::Value(@ast.Value::Bool(b)) =>
      match cond.kind {
        @ast.ConditionKind::When =>
          @ast.PartialValue::Value(@ast.Value::Bool(b))
        @ast.ConditionKind::Unless =>
          @ast.PartialValue::Value(@ast.Value::Bool(!b))
      }
    @ast.PartialValue::Value(_) =>
      @ast.PartialValue::Value(@ast.Value::Bool(false))
    @ast.PartialValue::Residual(re) =>
      match cond.kind {
        @ast.ConditionKind::When => @ast.PartialValue::Residual(re)
        @ast.ConditionKind::Unless =>
          @ast.PartialValue::Residual(
            @ast.Expr::UnaryApp(@ast.UnaryOp::Not, re),
          )
      }
  }
}

///|
/// Convert a ScopeConstraint + Unknown Expr into an Expr condition.
/// For example: Eq(User::"alice") + Unknown("principal") → principal == User::"alice"
fn scope_to_expr(sc : @ast.ScopeConstraint, e : @ast.Expr) -> @ast.Expr {
  match sc {
    @ast.ScopeConstraint::All => @ast.Expr::Lit(@ast.Literal::Bool(true))
    @ast.ScopeConstraint::Eq(uid) =>
      @ast.Expr::BinaryApp(
        @ast.BinaryOp::Eq,
        e,
        @ast.Expr::Lit(@ast.Literal::EntityUID(uid)),
      )
    @ast.ScopeConstraint::In(parent) =>
      @ast.Expr::BinaryApp(
        @ast.BinaryOp::In_,
        e,
        @ast.Expr::Lit(@ast.Literal::EntityUID(parent)),
      )
    @ast.ScopeConstraint::InSet(uids) =>
      @ast.Expr::BinaryApp(
        @ast.BinaryOp::In_,
        e,
        @ast.Expr::Set(
          uids.map(fn(uid) { @ast.Expr::Lit(@ast.Literal::EntityUID(uid)) }),
        ),
      )
    @ast.ScopeConstraint::Is(ty) => @ast.Expr::Is(e, ty)
    @ast.ScopeConstraint::IsIn(ty, parent) =>
      @ast.Expr::And(
        @ast.Expr::Is(e, ty),
        @ast.Expr::BinaryApp(
          @ast.BinaryOp::In_,
          e,
          @ast.Expr::Lit(@ast.Literal::EntityUID(parent)),
        ),
      )
  }
}

///|
/// Build an AND chain from a list of residual expressions.
fn merge_residuals(residuals : Array[@ast.Expr]) -> @ast.Expr {
  if residuals.length() == 0 {
    @ast.Expr::Lit(@ast.Literal::Bool(true))
  } else if residuals.length() == 1 {
    residuals[0]
  } else {
    let mut acc = residuals[0]
    for i = 1; i < residuals.length(); i = i + 1 {
      acc = @ast.Expr::And(acc, residuals[i])
    }
    acc
  }
}

///|
/// Evaluate a single policy against a Request and EntityStore.
/// Returns:
///   Value(Bool(true)) — policy satisfied (scope matched, all conditions passed)
///   Value(Bool(false)) — policy not satisfied (scope didn't match, or condition failed)
///   Residual(Expr) — partial eval: scope matched but some conditions are residual
///   raise EvalError — evaluation error
pub fn[S : EntityStore] eval_policy(
  p : @ast.Policy,
  req : Request,
  store : S,
) -> @ast.PartialValue raise EvalError {
  // Check scope constraints.
  // Unknown PARC slots generate residual conditions instead of concrete checks.
  let residuals : Array[@ast.Expr] = []
  match req.principal {
    EntityUIDEntry::Concrete(uid) =>
      if !scope_match(p.principal, uid, store) {
        return @ast.PartialValue::Value(@ast.Value::Bool(false))
      }
    EntityUIDEntry::Unknown(ty) =>
      residuals.push(
        scope_to_expr(
          p.principal,
          @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(ty))),
        ),
      )
  }
  match req.action {
    EntityUIDEntry::Concrete(uid) =>
      if !scope_match(p.action, uid, store) {
        return @ast.PartialValue::Value(@ast.Value::Bool(false))
      }
    EntityUIDEntry::Unknown(ty) =>
      residuals.push(
        scope_to_expr(
          p.action,
          @ast.Expr::Unknown("action", Some(@ast.Type::Entity(ty))),
        ),
      )
  }
  match req.resource {
    EntityUIDEntry::Concrete(uid) =>
      if !scope_match(p.resource, uid, store) {
        return @ast.PartialValue::Value(@ast.Value::Bool(false))
      }
    EntityUIDEntry::Unknown(ty) =>
      residuals.push(
        scope_to_expr(
          p.resource,
          @ast.Expr::Unknown("resource", Some(@ast.Type::Entity(ty))),
        ),
      )
  }

  // Evaluate conditions in order, accumulating into shared residuals array
  for i = 0; i < p.conditions.length(); i = i + 1 {
    let cond = p.conditions[i]
    match eval_single_condition(cond, req, store) {
      @ast.PartialValue::Value(@ast.Value::Bool(true)) => continue
      @ast.PartialValue::Value(@ast.Value::Bool(false)) =>
        return @ast.PartialValue::Value(@ast.Value::Bool(false))
      @ast.PartialValue::Value(_) =>
        return @ast.PartialValue::Value(@ast.Value::Bool(false))
      @ast.PartialValue::Residual(re) => {
        residuals.push(re)
        continue
      }
    }
  }

  if residuals.length() == 0 {
    @ast.PartialValue::Value(@ast.Value::Bool(true))
  } else {
    @ast.PartialValue::Residual(merge_residuals(residuals))
  }
}
