// Authorizer — evaluate + reauthorize + concretize pipeline.
// Reference: cedar-policy-core/src/authorizer.rs

// ---------------------------------------------------------------------------
// Authorization output types
// ---------------------------------------------------------------------------

///|
/// Authorization decision.
pub(all) enum Decision {
  Allow
  Deny
} derive(Debug, Eq)

///|
/// Diagnostic — identifying which policy caused a reason or error.
pub(all) struct DiagnosticReason {
  policy_id : String
  position : @ast.Position
} derive(Debug, Eq)

///|
/// Evaluation error for a specific policy.
pub(all) struct DiagnosticError {
  policy_id : String
  position : @ast.Position
  message : String
} derive(Debug, Eq)

///|
/// Full result of an authorization request.
pub(all) struct AuthorizationResult {
  decision : Decision
  determining_policies : Array[DiagnosticReason]
  errors : Array[DiagnosticError]
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// PartialAuthorizationAnswer — rich intermediate result
// ---------------------------------------------------------------------------

///|
/// Record of a single policy that fully satisfied (scope matched + all conditions passed).
struct DecisionRecord {
  policy_id : String
  effect : @ast.PolicyEffect
} derive(Debug, Eq)

///|
/// Record of a single policy where some conditions were residual (partial eval).
struct ResidualRecord {
  policy_id : String
  effect : @ast.PolicyEffect
  expr : @ast.Expr
} derive(Debug, Eq)

///|
/// Rich result of evaluating all policies against a Request.
/// Holds satisfied decisions, residuals, and errors separately
/// so downstream can concretize / reauthorize / sqlize as needed.
pub(all) struct PartialAuthorizationAnswer {
  satisfied : Array[DecisionRecord]
  residuals : Array[ResidualRecord]
  errors : Array[DiagnosticError]
} derive(Debug)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
fn eval_error_message(e : @evaluator.EvalError) -> String {
  match e {
    @evaluator.TypeMismatch(msg) => "TypeMismatch: \{msg}"
    @evaluator.IntegerOverflow => "IntegerOverflow"
    @evaluator.EntityNotFound(msg) => "EntityNotFound: \{msg}"
    @evaluator.InvalidOperator(msg) => "InvalidOperator: \{msg}"
    @evaluator.ExtensionNotSupported(msg) => "ExtensionNotSupported: \{msg}"
    @evaluator.SlotNotSupported => "SlotNotSupported"
  }
}

///|
fn make_diag_error(policy_id : String, msg : String) -> DiagnosticError {
  DiagnosticError::{
    policy_id,
    position: @ast.Position::{ filename: "", offset: 0, line: 0, column: 0 },
    message: msg,
  }
}

///|
fn make_diag_reason(policy_id : String) -> DiagnosticReason {
  DiagnosticReason::{
    policy_id,
    position: @ast.Position::{ filename: "", offset: 0, line: 0, column: 0 },
  }
}

// ---------------------------------------------------------------------------
// evaluate — first pass: evaluate all policies, produce PartialAuthorizationAnswer
// ---------------------------------------------------------------------------

///|
/// Evaluate all policies against a Request. Returns a rich PartialAuthorizationAnswer
/// that preserves residuals and errors for downstream processing.
pub fn[S : @evaluator.EntityStore] evaluate(
  req : @evaluator.Request,
  policies : Iter[@ast.Policy],
  store : S,
) -> PartialAuthorizationAnswer {
  let satisfied : Array[DecisionRecord] = []
  let residuals : Array[ResidualRecord] = []
  let errors : Array[DiagnosticError] = []

  for policy in policies {
    let result = @evaluator.eval_policy(policy, req, store) catch {
      e => {
        errors.push(make_diag_error(policy.id, eval_error_message(e)))
        continue
      }
    }
    match result {
      @ast.PartialValue::Value(@ast.Value::Bool(true)) =>
        satisfied.push(DecisionRecord::{
          policy_id: policy.id,
          effect: policy.effect,
        })
      @ast.PartialValue::Value(@ast.Value::Bool(false)) => continue
      @ast.PartialValue::Value(_) => continue
      @ast.PartialValue::Residual(re) =>
        residuals.push(ResidualRecord::{
          policy_id: policy.id,
          effect: policy.effect,
          expr: re,
        })
    }
  }

  PartialAuthorizationAnswer::{ satisfied, residuals, errors }
}

// ---------------------------------------------------------------------------
// reauthorize — re-evaluate residual policies with expanded information
// ---------------------------------------------------------------------------

///|
/// Substitute `Unknown(name)` nodes in an expression with concrete values from the mapping.
/// Unknowns that are not in the mapping are left as-is.
fn substitute_unknowns(
  expr : @ast.Expr,
  mapping : Map[String, @ast.Value],
) -> @ast.Expr {
  match expr {
    @ast.Expr::Unknown(name, _) =>
      match mapping.get(name) {
        Some(v) => @evaluator.value_to_expr(v)
        None => expr
      }
    @ast.Expr::Lit(_) | @ast.Expr::Var(_) | @ast.Expr::Slot(_) => expr
    @ast.Expr::If(c, t, e) =>
      @ast.Expr::If(
        substitute_unknowns(c, mapping),
        substitute_unknowns(t, mapping),
        substitute_unknowns(e, mapping),
      )
    @ast.Expr::And(l, r) =>
      @ast.Expr::And(
        substitute_unknowns(l, mapping),
        substitute_unknowns(r, mapping),
      )
    @ast.Expr::Or(l, r) =>
      @ast.Expr::Or(
        substitute_unknowns(l, mapping),
        substitute_unknowns(r, mapping),
      )
    @ast.Expr::UnaryApp(op, e) =>
      @ast.Expr::UnaryApp(op, substitute_unknowns(e, mapping))
    @ast.Expr::BinaryApp(op, l, r) =>
      @ast.Expr::BinaryApp(
        op,
        substitute_unknowns(l, mapping),
        substitute_unknowns(r, mapping),
      )
    @ast.Expr::GetAttr(e, a) =>
      @ast.Expr::GetAttr(substitute_unknowns(e, mapping), a)
    @ast.Expr::HasAttr(e, a) =>
      @ast.Expr::HasAttr(substitute_unknowns(e, mapping), a)
    @ast.Expr::GetTag(e, t) =>
      @ast.Expr::GetTag(
        substitute_unknowns(e, mapping),
        substitute_unknowns(t, mapping),
      )
    @ast.Expr::HasTag(e, t) =>
      @ast.Expr::HasTag(
        substitute_unknowns(e, mapping),
        substitute_unknowns(t, mapping),
      )
    @ast.Expr::Like(e, p) => @ast.Expr::Like(substitute_unknowns(e, mapping), p)
    @ast.Expr::Is(e, ty) => @ast.Expr::Is(substitute_unknowns(e, mapping), ty)
    @ast.Expr::Set(elems) =>
      @ast.Expr::Set(elems.map(fn(e) { substitute_unknowns(e, mapping) }))
    @ast.Expr::Record(pairs) =>
      @ast.Expr::Record(
        pairs.map(fn(p) { (p.0, substitute_unknowns(p.1, mapping)) }),
      )
    @ast.Expr::ExtensionApp(name, args) =>
      @ast.Expr::ExtensionApp(
        name,
        args.map(fn(e) { substitute_unknowns(e, mapping) }),
      )
  }
}

///|
/// Re-evaluate residual policies from a previous round, with an expanded entity
/// store and/or a mapping from unknown names to concrete values.
///
/// The `mapping` parameter handles expression-level `Unknown("x")` nodes
/// (e.g., context values that were unknown in the first pass but are now known).
/// The `store` parameter provides expanded entity hierarchy (e.g., after entity
/// slicing fetched missing entities).
///
/// Satisfied policies from the prior round are carried forward unconditionally.
pub fn[S : @evaluator.EntityStore] PartialAuthorizationAnswer::reauthorize(
  self : PartialAuthorizationAnswer,
  req : @evaluator.Request,
  store : S,
  mapping : Map[String, @ast.Value],
) -> PartialAuthorizationAnswer {
  let new_satisfied : Array[DecisionRecord] = []
  let new_residuals : Array[ResidualRecord] = []
  let new_errors : Array[DiagnosticError] = []

  for rec in self.residuals {
    let resolved = substitute_unknowns(rec.expr, mapping)
    let result = @evaluator.eval_expr(resolved, req, store) catch {
      e => {
        new_errors.push(make_diag_error(rec.policy_id, eval_error_message(e)))
        continue
      }
    }
    match result {
      @ast.PartialValue::Value(@ast.Value::Bool(true)) =>
        new_satisfied.push(DecisionRecord::{
          policy_id: rec.policy_id,
          effect: rec.effect,
        })
      @ast.PartialValue::Value(@ast.Value::Bool(false)) => continue
      @ast.PartialValue::Value(_) => continue
      @ast.PartialValue::Residual(re) =>
        new_residuals.push(ResidualRecord::{
          policy_id: rec.policy_id,
          effect: rec.effect,
          expr: re,
        })
    }
  }

  PartialAuthorizationAnswer::{
    satisfied: self.satisfied + new_satisfied,
    residuals: new_residuals,
    errors: self.errors + new_errors,
  }
}

// ---------------------------------------------------------------------------
// concretize — terminal pass: extract binary decision from PartialAuthorizationAnswer
// ---------------------------------------------------------------------------

///|
/// Concretize a PartialAuthorizationAnswer into a binary AuthorizationResult.
/// Permit + no satisfied Forbid → Allow; otherwise → Deny.
/// Residual policies are treated as non-determining (they don't count toward Allow).
pub fn PartialAuthorizationAnswer::concretize(
  self : PartialAuthorizationAnswer,
) -> AuthorizationResult {
  let mut has_permit = false
  let mut has_forbid = false
  let determining : Array[DiagnosticReason] = []

  for rec in self.satisfied {
    determining.push(make_diag_reason(rec.policy_id))
    match rec.effect {
      @ast.PolicyEffect::Permit => has_permit = true
      @ast.PolicyEffect::Forbid => has_forbid = true
    }
  }

  let decision = if has_permit && !has_forbid {
    Decision::Allow
  } else {
    Decision::Deny
  }

  AuthorizationResult::{
    decision,
    determining_policies: determining,
    errors: self.errors,
  }
}

// ---------------------------------------------------------------------------
// is_authorized — convenience: evaluate + concretize
// ---------------------------------------------------------------------------

///|
/// Evaluate policies and produce a binary authorization decision.
/// Convenience that composes evaluate() + concretize().
pub fn[S : @evaluator.EntityStore] is_authorized(
  req : @evaluator.Request,
  policies : Iter[@ast.Policy],
  store : S,
) -> AuthorizationResult {
  evaluate(req, policies, store).concretize()
}
