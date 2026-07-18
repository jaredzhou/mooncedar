// Top-level API — import `jaredzhou/mooncedar` to get these.

// ---------------------------------------------------------------------------
// Type aliases from sub-packages
// ---------------------------------------------------------------------------

///|
/// A Cedar expression AST node.
pub type Expr = @ast.Expr

///|
/// A Cedar policy.
pub type Policy = @ast.Policy

///|
/// Policy effect: Permit or Forbid.
pub type PolicyEffect = @ast.PolicyEffect

///|
/// A unique entity identifier, e.g. User::"alice".
pub type EntityUID = @ast.EntityUID

///|
/// An entity type name.
pub type EntityType = @ast.EntityType

///|
/// Application entity with attrs, tags, and parents.
pub type Entity = @ast.Entity

///|
/// A runtime Cedar value.
pub type Value = @ast.Value

///|
/// The Cedar type system (Bool, Long, String, Set, Record, Entity, Extension).
pub type Type = @ast.Type

///|
/// Partial evaluation result: concrete Value or residual Expr.
pub type PartialValue = @ast.PartialValue

///|
/// A scope constraint on principal, action, or resource.
pub type ScopeConstraint = @ast.ScopeConstraint

///|
/// A when/unless condition in a policy.
pub type Condition = @ast.Condition

///|
/// The PARC authorization request.
pub type Request = @evaluator.Request

///|
/// A PARC slot: either a known EntityUID or a typed Unknown.
pub type EntityUIDEntry = @evaluator.EntityUIDEntry

///|
/// Request context: Concrete, Unknown, or Partial.
pub type Context = @evaluator.Context

///|
/// Evaluation error.
pub type EvalError = @evaluator.EvalError

///|
/// Parser error.
pub type ParseError = @parser.ParseError

// ---------------------------------------------------------------------------
// Parser & stringify
// ---------------------------------------------------------------------------

///|
/// Parse one or more Cedar policies from source text.
pub fn parse_policies(
  src : String,
) -> Array[@ast.Policy] raise @parser.ParseError {
  @parser.parse_policies(src)
}

///|
/// Convert a policy to Cedar source text.
pub fn stringify(p : @ast.Policy) -> String {
  @parser.stringify(p)
}

///|
/// Convert an expression to Cedar source text.
pub fn stringify_expr(e : @ast.Expr) -> String {
  @parser.stringify_expr(e)
}

// ---------------------------------------------------------------------------
// Expression builder (re-exported from @ast)
// ---------------------------------------------------------------------------

///|
/// Leaf constructors
pub fn expr_bool(b : Bool) -> @ast.Expr {
  @ast.expr_bool(b)
}

///|
pub fn expr_long(l : Int64) -> @ast.Expr {
  @ast.expr_long(l)
}

///|
pub fn expr_str(s : String) -> @ast.Expr {
  @ast.expr_str(s)
}

///|
pub fn expr_euid(type_ : String, id : String) -> @ast.Expr {
  @ast.expr_euid(type_, id)
}

///|
pub fn expr_principal() -> @ast.Expr {
  @ast.expr_principal()
}

///|
pub fn expr_action() -> @ast.Expr {
  @ast.expr_action()
}

///|
pub fn expr_resource() -> @ast.Expr {
  @ast.expr_resource()
}

///|
pub fn expr_context() -> @ast.Expr {
  @ast.expr_context()
}

///|
pub fn expr_unknown(name : String) -> @ast.Expr {
  @ast.expr_unknown(name)
}

///|
/// Non-chaining constructors
pub fn expr_if(cond : @ast.Expr, t : @ast.Expr, e : @ast.Expr) -> @ast.Expr {
  @ast.expr_if(cond, t, e)
}

///|
pub fn expr_not(e : @ast.Expr) -> @ast.Expr {
  @ast.expr_not(e)
}

///|
pub fn expr_neg(e : @ast.Expr) -> @ast.Expr {
  @ast.expr_neg(e)
}

///|
pub fn expr_is_empty(e : @ast.Expr) -> @ast.Expr {
  @ast.expr_is_empty(e)
}

///|
pub fn expr_set(elements : Array[@ast.Expr]) -> @ast.Expr {
  @ast.expr_set(elements)
}

///|
pub fn expr_record(pairs : Array[(String, @ast.Expr)]) -> @ast.Expr {
  @ast.expr_record(pairs)
}

///|
pub fn expr_ext_call(name : @ast.Name, args : Array[@ast.Expr]) -> @ast.Expr {
  @ast.expr_ext_call(name, args)
}

// ---------------------------------------------------------------------------
// Policy builder (re-exported from @ast)
// ---------------------------------------------------------------------------

///|
/// Create a default (permit-all) Policy struct.
pub fn default_policy() -> @ast.Policy {
  @ast.default()
}

///|
/// Create an EntityUID in builder context.
pub fn entity_uid(type_ : String, id : String) -> @ast.EntityUID {
  @ast.entity_uid(type_, id)
}

///|
/// Create an EntityType in builder context.
pub fn entity_type(name : String) -> @ast.EntityType {
  @ast.entity_type(name)
}
