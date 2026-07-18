// Evaluator types — Dereference, EntityStore, EvalError.
// References:
//   Rust: cedar-policy-core/src/evaluator.rs
//   Go:   cedar-go/internal/eval/

// ---------------------------------------------------------------------------
// Dereference — entity lookup result
// ---------------------------------------------------------------------------

///|
/// Result of looking up an entity in the store.
pub(all) enum Dereference {
  Data(@ast.Entity)
  NoSuchEntity
  Residual(@ast.Expr)
} derive(Debug, Eq)

///|
/// Errors that can occur during expression evaluation.
pub(all) suberror EvalError {
  TypeMismatch(String)
  IntegerOverflow
  EntityNotFound(String)
  InvalidOperator(String)
  ExtensionNotSupported(String)
  SlotNotSupported
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Request — PARC slots + context
// ---------------------------------------------------------------------------

///|
/// A PARC slot: either a known EntityUID (concrete eval) or a typed Unknown (partial eval).
pub(all) enum EntityUIDEntry {
  Concrete(@ast.EntityUID)
  Unknown(@ast.EntityType)
} derive(Debug, Eq)

///|
/// Helper: construct a concrete EntityUIDEntry.
pub fn concrete_uid(type_ : String, id : String) -> EntityUIDEntry {
  Concrete(@ast.EntityUID::{ type_, id })
}

///|
/// construct a unknown EntityUIDEntry.
pub fn unknown_uid(type_ : String) -> EntityUIDEntry {
  Unknown(@ast.EntityType(type_))
}

///|
/// Request context — three states matching Rust's CPE:
/// - Concrete(Value::Record(...)): fully known context
/// - Unknown(Expr): entirely unknown (e.g., Expr::Unknown("context", None))
/// - Partial(Expr): partially known, containing an Expr::Record where
///   individual fields may be Expr::Unknown nodes.
pub(all) enum Context {
  Concrete(@ast.Value)
  Unknown
  Partial(@ast.Expr)
} derive(Debug, Eq)

///|
/// construct a concrete Context from a Value.
pub fn concrete_context(value : @ast.Value) -> Context {
  Concrete(value)
}

///|
/// construct an unknown Context.
pub fn unknown_context() -> Context {
  Unknown
}

///|
/// construct a partial Context from an Expr.
pub fn partial_context(expr : @ast.Expr) -> Context {
  Partial(expr)
}

///|
/// The PARC authorization request.
pub(all) struct Request {
  principal : EntityUIDEntry
  action : EntityUIDEntry
  resource : EntityUIDEntry
  context : Context
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// EntityStore trait — pluggable entity storage
// ---------------------------------------------------------------------------

///|
/// Pluggable entity storage. Implement this trait to provide entity lookups
/// from any backing store (in-memory Map, database, cache, etc.).
pub(open) trait EntityStore {
  fn get_entity(Self, @ast.EntityUID) -> @ast.Entity?
}
