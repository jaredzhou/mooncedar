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
pub fn bool(b : Bool) -> @ast.Expr {
  @ast.bool(b)
}

///|
pub fn long(l : Int64) -> @ast.Expr {
  @ast.long(l)
}

///|
pub fn str(s : String) -> @ast.Expr {
  @ast.str(s)
}

///|
pub fn euid(type_ : String, id : String) -> @ast.Expr {
  @ast.euid(type_, id)
}

///|
pub fn principal() -> @ast.Expr {
  @ast.principal()
}

///|
pub fn action() -> @ast.Expr {
  @ast.action()
}

///|
pub fn resource() -> @ast.Expr {
  @ast.resource()
}

///|
pub fn context() -> @ast.Expr {
  @ast.context()
}

///|
pub fn unknown(name : String, typ? : @ast.Type) -> @ast.Expr {
  match typ {
    Some(t) => @ast.unknown(name, typ=t)
    None => @ast.unknown(name)
  }
}

///|
/// Non-chaining constructors
pub fn if_(cond : @ast.Expr, t : @ast.Expr, e : @ast.Expr) -> @ast.Expr {
  @ast.if_(cond, t, e)
}

///|
pub fn not_(e : @ast.Expr) -> @ast.Expr {
  @ast.not_(e)
}

///|
pub fn neg(e : @ast.Expr) -> @ast.Expr {
  @ast.neg(e)
}

///|
pub fn is_empty(e : @ast.Expr) -> @ast.Expr {
  @ast.is_empty(e)
}

///|
pub fn set(elements : Array[@ast.Expr]) -> @ast.Expr {
  @ast.set(elements)
}

///|
pub fn record(pairs : Array[(String, @ast.Expr)]) -> @ast.Expr {
  @ast.record(pairs)
}

///|
pub fn ext_call(name : @ast.Name, args : Array[@ast.Expr]) -> @ast.Expr {
  @ast.ext_call(name, args)
}

// ---------------------------------------------------------------------------
// Evaluator (re-exported from @evaluator)
// ---------------------------------------------------------------------------

///|
/// Evaluate a Cedar expression with the given request and entity store.
/// Returns Value(concrete) for fully-reducible expressions, or Residual(expr)
/// for expressions that cannot be fully reduced (partial evaluation).
pub fn[S : @evaluator.EntityStore] eval_expr(
  expr : @ast.Expr,
  req : @evaluator.Request,
  store : S,
) -> @ast.PartialValue raise @evaluator.EvalError {
  @evaluator.eval_expr(expr, req, store)
}

///|
/// Convert a concrete Value back into an Expr AST node.
pub fn value_to_expr(v : @ast.Value) -> @ast.Expr {
  @evaluator.value_to_expr(v)
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
