// Evaluator tests — covering all components.
// Reference: cedar-policy-core tests

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
fn entity(
  uid : @ast.EntityUID,
  attrs : Map[String, @ast.Value],
  tags : Map[String, @ast.Value],
  parents : Array[@ast.EntityUID],
) -> @ast.Entity {
  @ast.Entity::{ uid, attrs, tags, parents }
}

///|
/// Local entity store for tests (avoids pulling in MapEntityStore from root).
struct TestStore {
  entities : Map[@ast.EntityUID, @ast.Entity]
} derive(Debug, Eq)

///|
impl EntityStore for TestStore with fn get_entity(self, uid : @ast.EntityUID) -> @ast.Entity? {
  self.entities.get(uid)
}

///|
fn empty_store() -> TestStore {
  TestStore::{ entities: Map([]) }
}

///|
fn empty_req() -> Request {
  Request::{
    principal: EntityUIDEntry::Concrete(@ast.EntityUID::{ type_: "", id: "" }),
    action: EntityUIDEntry::Concrete(@ast.EntityUID::{ type_: "", id: "" }),
    resource: EntityUIDEntry::Concrete(@ast.EntityUID::{ type_: "", id: "" }),
    context: Context::Concrete(@ast.Value::Record(Map([]))),
  }
}

///|
fn uid(type_ : String, id : String) -> @ast.EntityUID {
  @ast.EntityUID::{ type_, id }
}

///|
fn eval_simple(src : @ast.Expr) -> @ast.PartialValue raise EvalError {
  eval_expr(src, empty_req(), empty_store())
}

// ---------------------------------------------------------------------------
// Pattern matching tests
// ---------------------------------------------------------------------------

///|
test "wildcard_match: exact match" {
  let p = @ast.Pattern::{ elements: [@ast.PatternElem::Char('a')] }
  @debug.assert_eq(true, wildcard_match("a", p))
  @debug.assert_eq(false, wildcard_match("b", p))
}

///|
test "wildcard_match: star prefix" {
  let p = @ast.Pattern::{
    elements: [@ast.PatternElem::Wildcard, @ast.PatternElem::Char('x')],
  }
  @debug.assert_eq(true, wildcard_match("x", p))
  @debug.assert_eq(true, wildcard_match("ax", p))
  @debug.assert_eq(true, wildcard_match("abcx", p))
  @debug.assert_eq(false, wildcard_match("xa", p))
}

///|
test "wildcard_match: star suffix" {
  let p = @ast.Pattern::{
    elements: [@ast.PatternElem::Char('a'), @ast.PatternElem::Wildcard],
  }
  @debug.assert_eq(true, wildcard_match("a", p))
  @debug.assert_eq(true, wildcard_match("ab", p))
  @debug.assert_eq(true, wildcard_match("abc", p))
  @debug.assert_eq(false, wildcard_match("ba", p))
}

///|
test "wildcard_match: star middle" {
  let p = @ast.Pattern::{
    elements: [
      @ast.PatternElem::Char('a'),
      @ast.PatternElem::Wildcard,
      @ast.PatternElem::Char('z'),
    ],
  }
  @debug.assert_eq(true, wildcard_match("az", p))
  @debug.assert_eq(true, wildcard_match("abcz", p))
  @debug.assert_eq(true, wildcard_match("abcxyz", p))
  @debug.assert_eq(false, wildcard_match("za", p))
}

///|
test "wildcard_match: multiple stars" {
  let p = @ast.Pattern::{
    elements: [
      @ast.PatternElem::Wildcard,
      @ast.PatternElem::Char('a'),
      @ast.PatternElem::Wildcard,
      @ast.PatternElem::Char('b'),
      @ast.PatternElem::Wildcard,
    ],
  }
  @debug.assert_eq(true, wildcard_match("ab", p))
  @debug.assert_eq(true, wildcard_match("xayb", p))
  @debug.assert_eq(true, wildcard_match("xaybz", p))
  @debug.assert_eq(false, wildcard_match("ba", p))
}

///|
test "wildcard_match: star only" {
  let p = @ast.Pattern::{ elements: [@ast.PatternElem::Wildcard] }
  @debug.assert_eq(true, wildcard_match("", p))
  @debug.assert_eq(true, wildcard_match("anything", p))
}

///|
test "wildcard_match: empty pattern" {
  let p = @ast.Pattern::{ elements: [] }
  @debug.assert_eq(true, wildcard_match("", p))
  @debug.assert_eq(false, wildcard_match("a", p))
}

///|
test "wildcard_match: escaped star" {
  let p = @ast.Pattern::{ elements: [@ast.PatternElem::Char('*')] }
  @debug.assert_eq(true, wildcard_match("*", p))
  @debug.assert_eq(false, wildcard_match("a", p))
}

// ---------------------------------------------------------------------------
// Operator tests
// ---------------------------------------------------------------------------

///|
test "eval_unary: Not true -> false" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::Not, @ast.Value::Bool(true)) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_unary: Not false -> true" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::Not, @ast.Value::Bool(false)) ==
    @ast.Value::Bool(true),
  )
}

///|
test "eval_unary: Not on non-Long raises" {
  let mut raised = false
  try eval_unary(@ast.UnaryOp::Not, @ast.Value::Long(42L)) |> ignore catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_unary: Neg on Long" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::Neg, @ast.Value::Long(42L)) ==
    @ast.Value::Long(-42L),
  )
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::Neg, @ast.Value::Long(-5L)) == @ast.Value::Long(5L),
  )
}

///|
test "eval_unary: Neg on non-Long raises" {
  let mut raised = false
  try eval_unary(@ast.UnaryOp::Neg, @ast.Value::Bool(true)) |> ignore catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_unary: IsEmpty on empty Set" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::IsEmpty, @ast.Value::Set([])) ==
    @ast.Value::Bool(true),
  )
}

///|
test "eval_unary: IsEmpty on non-empty Set" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::IsEmpty, @ast.Value::Set([@ast.Value::Bool(true)])) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_unary: IsEmpty on empty Record" {
  @debug.assert_eq(
    true,
    eval_unary(@ast.UnaryOp::IsEmpty, @ast.Value::Record(Map([]))) ==
    @ast.Value::Bool(true),
  )
}

///|
test "eval_binary: Eq same values" {
  @debug.assert_eq(
    true,
    eval_binary(
      @ast.BinaryOp::Eq,
      @ast.Value::Bool(true),
      @ast.Value::Bool(true),
    ) ==
    @ast.Value::Bool(true),
  )
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Eq, @ast.Value::Long(1L), @ast.Value::Long(1L)) ==
    @ast.Value::Bool(true),
  )
}

///|
test "eval_binary: Eq different values" {
  @debug.assert_eq(
    true,
    eval_binary(
      @ast.BinaryOp::Eq,
      @ast.Value::Bool(true),
      @ast.Value::Bool(false),
    ) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_binary: Eq different types" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Eq, @ast.Value::Bool(true), @ast.Value::Long(1L)) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_binary: Ne" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Ne, @ast.Value::Long(1L), @ast.Value::Long(2L)) ==
    @ast.Value::Bool(true),
  )
  @debug.assert_eq(
    true,
    eval_binary(
      @ast.BinaryOp::Ne,
      @ast.Value::Bool(true),
      @ast.Value::Bool(true),
    ) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_binary: Less/LessEq" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Less, @ast.Value::Long(1L), @ast.Value::Long(2L)) ==
    @ast.Value::Bool(true),
  )
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Less, @ast.Value::Long(2L), @ast.Value::Long(1L)) ==
    @ast.Value::Bool(false),
  )
  @debug.assert_eq(
    true,
    eval_binary(
      @ast.BinaryOp::LessEq,
      @ast.Value::Long(2L),
      @ast.Value::Long(2L),
    ) ==
    @ast.Value::Bool(true),
  )
}

///|
test "eval_binary: comparison non-Long raises" {
  let mut raised = false
  try
    eval_binary(
      @ast.BinaryOp::Less,
      @ast.Value::Bool(true),
      @ast.Value::Bool(false),
    )
    |> ignore
  catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_binary: Add" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Add, @ast.Value::Long(2L), @ast.Value::Long(3L)) ==
    @ast.Value::Long(5L),
  )
}

///|
test "eval_binary: Sub" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Sub, @ast.Value::Long(10L), @ast.Value::Long(3L)) ==
    @ast.Value::Long(7L),
  )
}

///|
test "eval_binary: Mul" {
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Mul, @ast.Value::Long(4L), @ast.Value::Long(5L)) ==
    @ast.Value::Long(20L),
  )
}

///|
test "eval_binary: arithmetic non-Long raises" {
  let mut raised = false
  try
    eval_binary(
      @ast.BinaryOp::Add,
      @ast.Value::Bool(true),
      @ast.Value::Long(1L),
    )
    |> ignore
  catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_binary: Contains in Set" {
  let s = @ast.Value::Set([
    @ast.Value::Long(1L),
    @ast.Value::Long(2L),
    @ast.Value::Long(3L),
  ])
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Contains, s, @ast.Value::Long(2L)) ==
    @ast.Value::Bool(true),
  )
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::Contains, s, @ast.Value::Long(4L)) ==
    @ast.Value::Bool(false),
  )
}

///|
test "eval_binary: ContainsAll" {
  let s = @ast.Value::Set([
    @ast.Value::Long(1L),
    @ast.Value::Long(2L),
    @ast.Value::Long(3L),
  ])
  let sub = @ast.Value::Set([@ast.Value::Long(1L), @ast.Value::Long(2L)])
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::ContainsAll, s, sub) == @ast.Value::Bool(true),
  )
  let extra = @ast.Value::Set([@ast.Value::Long(1L), @ast.Value::Long(4L)])
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::ContainsAll, s, extra) == @ast.Value::Bool(false),
  )
}

///|
test "eval_binary: ContainsAny" {
  let s = @ast.Value::Set([@ast.Value::Long(1L), @ast.Value::Long(2L)])
  let overlap = @ast.Value::Set([@ast.Value::Long(2L), @ast.Value::Long(3L)])
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::ContainsAny, s, overlap) ==
    @ast.Value::Bool(true),
  )
  let disjoin = @ast.Value::Set([@ast.Value::Long(3L), @ast.Value::Long(4L)])
  @debug.assert_eq(
    true,
    eval_binary(@ast.BinaryOp::ContainsAny, s, disjoin) ==
    @ast.Value::Bool(false),
  )
}

// ---------------------------------------------------------------------------
// Scope evaluation tests
// ---------------------------------------------------------------------------

///|
test "scope_match: All" {
  let store = empty_store()
  @debug.assert_eq(
    true,
    scope_match(@ast.ScopeConstraint::All, uid("User", "alice"), store),
  )
}

///|
test "scope_match: Eq matching" {
  let store = empty_store()
  @debug.assert_eq(
    true,
    scope_match(
      @ast.ScopeConstraint::Eq(uid("User", "alice")),
      uid("User", "alice"),
      store,
    ),
  )
}

///|
test "scope_match: Eq non-matching" {
  let store = empty_store()
  @debug.assert_eq(
    false,
    scope_match(
      @ast.ScopeConstraint::Eq(uid("User", "alice")),
      uid("User", "bob"),
      store,
    ),
  )
}

///|
test "scope_match: In descendant via hierarchy" {
  let e = entity(uid("User", "alice"), Map([]), Map([]), [uid("Team", "admins")])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), e)]) }
  @debug.assert_eq(
    true,
    scope_match(
      @ast.ScopeConstraint::In(uid("Team", "admins")),
      uid("User", "alice"),
      store,
    ),
  )
}

///|
test "scope_match: In not in hierarchy" {
  let store = empty_store()
  @debug.assert_eq(
    false,
    scope_match(
      @ast.ScopeConstraint::In(uid("Team", "admins")),
      uid("User", "alice"),
      store,
    ),
  )
}

///|
test "scope_match: InSet" {
  let store = empty_store()
  let sc = @ast.ScopeConstraint::InSet([
    uid("PhotoOp", "view"),
    uid("PhotoOp", "delete"),
  ])
  @debug.assert_eq(true, scope_match(sc, uid("PhotoOp", "view"), store))
  @debug.assert_eq(false, scope_match(sc, uid("PhotoOp", "edit"), store))
}

///|
test "scope_match: Is" {
  let store = empty_store()
  @debug.assert_eq(
    true,
    scope_match(
      @ast.ScopeConstraint::Is(@ast.EntityType("User")),
      uid("User", "alice"),
      store,
    ),
  )
  @debug.assert_eq(
    false,
    scope_match(
      @ast.ScopeConstraint::Is(@ast.EntityType("Photo")),
      uid("User", "alice"),
      store,
    ),
  )
}

///|
test "scope_match: IsIn" {
  let e = entity(uid("Photo", "sunset.jpg"), Map([]), Map([]), [
    uid("Album", "vacation"),
  ])
  let store = TestStore::{ entities: Map([(uid("Photo", "sunset.jpg"), e)]) }
  let sc = @ast.ScopeConstraint::IsIn(
    @ast.EntityType("Photo"),
    uid("Album", "vacation"),
  )
  @debug.assert_eq(true, scope_match(sc, uid("Photo", "sunset.jpg"), store))
  @debug.assert_eq(false, scope_match(sc, uid("User", "alice"), store))
}

///|
test "is_descendant: reflexive" {
  let store = empty_store()
  @debug.assert_eq(
    true,
    is_descendant(uid("User", "alice"), uid("User", "alice"), store),
  )
}

///|
test "is_descendant: direct parent" {
  let e = entity(uid("Photo", "sunset.jpg"), Map([]), Map([]), [
    uid("Album", "vacation"),
  ])
  let store = TestStore::{ entities: Map([(uid("Photo", "sunset.jpg"), e)]) }
  @debug.assert_eq(
    true,
    is_descendant(uid("Photo", "sunset.jpg"), uid("Album", "vacation"), store),
  )
}

///|
test "is_descendant: not found" {
  let store = empty_store()
  @debug.assert_eq(
    false,
    is_descendant(uid("User", "alice"), uid("Team", "admins"), store),
  )
}

///|
test "is_descendant: transitive" {
  let alice = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "engineering"),
  ])
  let eng = entity(uid("Team", "engineering"), Map([]), Map([]), [
    uid("Org", "corp"),
  ])
  let store = TestStore::{
    entities: Map([
      (uid("User", "alice"), alice),
      (uid("Team", "engineering"), eng),
    ]),
  }
  @debug.assert_eq(
    true,
    is_descendant(uid("User", "alice"), uid("Org", "corp"), store),
  )
}

// ---------------------------------------------------------------------------
// Expression evaluation tests
// ---------------------------------------------------------------------------

///|
test "eval_expr: Lit Bool" {
  let e = @ast.Expr::Lit(@ast.Literal::Bool(true))
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Lit Long" {
  let e = @ast.Expr::Lit(@ast.Literal::Long(42L))
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Long(42L))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Lit String" {
  let e = @ast.Expr::Lit(@ast.Literal::String("hello"))
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::String("hello"))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Lit EntityUID" {
  let e = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice")))
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::EntityUID(uid("User", "alice")))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Var principal" {
  let req = Request::{
    principal: concrete_uid("User", "alice"),
    action: concrete_uid("Action", "view"),
    resource: concrete_uid("Photo", "x.jpg"),
    context: Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let store = empty_store()
  match eval_expr(@ast.Expr::Var(@ast.VarKind::Principal), req, store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::EntityUID(uid("User", "alice")))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Var context" {
  let req = Request::{
    principal: concrete_uid("User", "a"),
    action: concrete_uid("Action", "v"),
    resource: concrete_uid("Photo", "x"),
    context: Context::Concrete(
      @ast.Value::Record(Map([("key", @ast.Value::String("val"))])),
    ),
  }
  let store = empty_store()
  match eval_expr(@ast.Expr::Var(@ast.VarKind::Context), req, store) {
    @ast.PartialValue::Value(@ast.Value::Record(map)) =>
      @debug.assert_eq(true, map.get("key") == Some(@ast.Value::String("val")))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: And both true" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: And short-circuit false" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Or both false" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Or short-circuit true" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: If true branch" {
  let e = @ast.Expr::If(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::Lit(@ast.Literal::Long(1L)),
    @ast.Expr::Lit(@ast.Literal::Long(2L)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Long(1L))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: If false branch" {
  let e = @ast.Expr::If(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.Expr::Lit(@ast.Literal::Long(1L)),
    @ast.Expr::Lit(@ast.Literal::Long(2L)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Long(2L))
    _ => @debug.assert_eq(true, false)
  }
}

// ---------------------------------------------------------------------------
// CPE short-circuit semantics (matching Rust cedar-policy-core)
// ---------------------------------------------------------------------------

///|
test "cpe: true && unknown preserves And wrapper" {
  // true && Unknown should NOT simplify to just Unknown — the And wrapper
  // ensures the runtime type check (residual must be Bool) is preserved.
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.expr_unknown("x"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(@ast.Expr::And(_, _)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe: false && unknown short-circuits" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.expr_unknown("x"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(false)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe: false || unknown preserves Or wrapper" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.expr_unknown("x"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(@ast.Expr::Or(_, _)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe: true || unknown short-circuits" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.expr_unknown("x"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(true)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe: residual && type_error is suppressed" {
  // When left is residual, right-side type errors must be suppressed
  // because if left eventually evaluates to false, the error is short-circuited.
  let e = @ast.Expr::And(
    @ast.expr_unknown("x"),
    @ast.Expr::ExtensionApp(@ast.Name::{ ns: ["ip"], name: "parse" }, [
      @ast.Expr::Lit(@ast.Literal::String("x")),
    ]),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe: residual || type_error is suppressed" {
  let e = @ast.Expr::Or(
    @ast.expr_unknown("x"),
    @ast.Expr::ExtensionApp(@ast.Name::{ ns: ["ip"], name: "parse" }, [
      @ast.Expr::Lit(@ast.Literal::String("x")),
    ]),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

// ---------------------------------------------------------------------------
// CPE And/Or: matching Rust and_semantics*, or_semantics*, partial_and_* tests
// ---------------------------------------------------------------------------

///|
test "cpe and_semantics1: false && (unknown && false) => false" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.Expr::And(
      @ast.expr_unknown("a"),
      @ast.Expr::Lit(@ast.Literal::Bool(false)),
    ),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(false)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe and_semantics2: true && (unknown && false) => residual" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::And(
      @ast.expr_unknown("a"),
      @ast.Expr::Lit(@ast.Literal::Bool(false)),
    ),
  )
  // true && residual → Residual(And(true, residual)), not simplified
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe or_semantics1: true || (unknown && false) => true" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::And(
      @ast.expr_unknown("a"),
      @ast.Expr::Lit(@ast.Literal::Bool(false)),
    ),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(true)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe or_semantics2: false || (unknown && false) => residual" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.Expr::And(
      @ast.expr_unknown("a"),
      @ast.Expr::Lit(@ast.Literal::Bool(false)),
    ),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe and_semantics4: residual && type_error => residual, error suppressed" {
  let e = @ast.Expr::And(
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Eq,
      @ast.expr_unknown("a"),
      @ast.Expr::Lit(@ast.Literal::Long(2L)),
    ),
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("hello")),
      @ast.Expr::Lit(@ast.Literal::Long(99L)),
    ),
  )
  // Left is residual (unknown == 2), right is type error (string && string)
  // Error on right must be suppressed
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_and_err_res: type_error && residual => error propagates" {
  let e = @ast.Expr::And(
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("a")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
    @ast.expr_unknown("x"),
  )
  // Left is type error (string + long), right doesn't matter
  let mut raised = false
  try eval_simple(e) |> ignore catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "cpe partial_or_err_res: type_error || residual => error propagates" {
  let e = @ast.Expr::Or(
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("a")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
    @ast.expr_unknown("x"),
  )
  let mut raised = false
  try eval_simple(e) |> ignore catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "cpe partial_and_true_res: true && residual => And(true, residual)" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.expr_unknown("a"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(@ast.Expr::And(l, r)) => {
      @debug.assert_eq(true, l == @ast.Expr::Lit(@ast.Literal::Bool(true)))
      @debug.assert_eq(true, r == @ast.expr_unknown("a"))
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_and_false_res: false && residual => false" {
  let e = @ast.Expr::And(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.expr_unknown("a"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(false)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_and_res_true: residual && true => And(residual, Lit(true))" {
  let e = @ast.Expr::And(
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_and_res_false: residual && false => And(res, false)" {
  let e = @ast.Expr::And(
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_and_res_err: residual && type_error => residual" {
  let e = @ast.Expr::And(
    @ast.expr_unknown("a"),
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("s")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_true_res: true || residual => true" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.expr_unknown("a"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Bool(true)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_false_res: false || residual => Or(false, residual)" {
  let e = @ast.Expr::Or(
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
    @ast.expr_unknown("a"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_res_true: residual || true => Or(res, true)" {
  let e = @ast.Expr::Or(
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_res_false: residual || false => Or(residual, Lit(false))" {
  let e = @ast.Expr::Or(
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Bool(false)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_res_res: residual || residual => Or(res, res)" {
  let e = @ast.Expr::Or(@ast.expr_unknown("a"), @ast.expr_unknown("b"))
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_or_res_err: residual || type_error => residual" {
  let e = @ast.Expr::Or(
    @ast.expr_unknown("a"),
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("s")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe if_semantics_residual_guard: if unknown then type_error else concrete" {
  // Guard is unknown → branching can't be decided. Both branches preserved.
  // Even though the then branch would type-error, we don't evaluate it yet.
  let e = @ast.Expr::If(
    @ast.expr_unknown("guard"),
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("x")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe if_semantics: if true then type_error else concrete => error propagates" {
  let e = @ast.Expr::If(
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
    @ast.Expr::BinaryApp(
      @ast.BinaryOp::Add,
      @ast.Expr::Lit(@ast.Literal::String("x")),
      @ast.Expr::Lit(@ast.Literal::Long(1L)),
    ),
    @ast.Expr::Lit(@ast.Literal::Long(10L)),
  )
  // Concrete true guard → take then branch → type error (1 && 2)
  let mut raised = false
  try eval_simple(e) |> ignore catch {
    TypeMismatch(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "cpe partial_binop: unknown + 3 => residual" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Add,
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Long(3L)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_binop: 3 + unknown => residual" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Add,
    @ast.Expr::Lit(@ast.Literal::Long(3L)),
    @ast.expr_unknown("b"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_binop: unknown == 2 => residual" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Eq,
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Long(2L)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_binop: 1 in unknown_set => residual" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Contains,
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("T", "x"))),
    @ast.expr_unknown("s"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_binop err_res: type_error + unknown => residual" {
  // Binary ops with one residual operand always produce residual — the
  // type error on the concrete side is not evaluated because the residual
  // side might change the result when concretized.
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Add,
    @ast.Expr::Lit(@ast.Literal::String("a")),
    @ast.expr_unknown("b"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_unop: !unknown => residual" {
  let e = @ast.Expr::UnaryApp(@ast.UnaryOp::Not, @ast.expr_unknown("a"))
  match eval_simple(e) {
    @ast.PartialValue::Residual(@ast.Expr::UnaryApp(@ast.UnaryOp::Not, _)) =>
      @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_is: unknown is EntityType => residual" {
  let e = @ast.Expr::Is(@ast.expr_unknown("a"), @ast.EntityType("User"))
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_like: unknown like pattern => residual" {
  let p = @ast.Pattern::{ elements: [@ast.PatternElem::Wildcard] }
  let e = @ast.Expr::Like(@ast.expr_unknown("a"), p)
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "cpe partial_set: [1, unknown, 3] => residual" {
  let e = @ast.Expr::Set([
    @ast.Expr::Lit(@ast.Literal::Long(1L)),
    @ast.expr_unknown("a"),
    @ast.Expr::Lit(@ast.Literal::Long(3L)),
  ])
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: UnaryApp Not" {
  let e = @ast.Expr::UnaryApp(
    @ast.UnaryOp::Not,
    @ast.Expr::Lit(@ast.Literal::Bool(true)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: BinaryApp Add" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Add,
    @ast.Expr::Lit(@ast.Literal::Long(3L)),
    @ast.Expr::Lit(@ast.Literal::Long(4L)),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Long(7L))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: BinaryApp Eq entities" {
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::Eq,
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "a"))),
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "a"))),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Like matching" {
  let pattern = @ast.Pattern::{
    elements: [@ast.PatternElem::Wildcard, @ast.PatternElem::Char('z')],
  }
  let e = @ast.Expr::Like(@ast.Expr::Lit(@ast.Literal::String("abcz")), pattern)
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Like non-matching" {
  let pattern = @ast.Pattern::{
    elements: [@ast.PatternElem::Char('a'), @ast.PatternElem::Wildcard],
  }
  let e = @ast.Expr::Like(@ast.Expr::Lit(@ast.Literal::String("xyz")), pattern)
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Is matching type" {
  let e = @ast.Expr::Is(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.EntityType("User"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Is non-matching type" {
  let e = @ast.Expr::Is(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.EntityType("Photo"),
  )
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: GetAttr from entity" {
  let ent = entity(
    uid("x", "y"),
    Map([("name", @ast.Value::String("alice"))]),
    Map([]),
    [],
  )
  let store = TestStore::{ entities: Map([(uid("x", "y"), ent)]) }
  let e = @ast.Expr::GetAttr(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("x", "y"))),
    "name",
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::String("alice"))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: HasAttr entity has attribute" {
  let ent = entity(
    uid("x", "y"),
    Map([("name", @ast.Value::String("alice"))]),
    Map([]),
    [],
  )
  let store = TestStore::{ entities: Map([(uid("x", "y"), ent)]) }
  let e = @ast.Expr::HasAttr(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("x", "y"))),
    "name",
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: HasAttr entity lacks attribute" {
  let ent = entity(uid("x", "y"), Map([]), Map([]), [])
  let store = TestStore::{ entities: Map([(uid("x", "y"), ent)]) }
  let e = @ast.Expr::HasAttr(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("x", "y"))),
    "missing",
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Set all concrete" {
  let e = @ast.Expr::Set([
    @ast.Expr::Lit(@ast.Literal::Long(1L)),
    @ast.Expr::Lit(@ast.Literal::Long(2L)),
    @ast.Expr::Lit(@ast.Literal::Long(3L)),
  ])
  match eval_simple(e) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(
        true,
        v ==
        @ast.Value::Set([
          @ast.Value::Long(1L),
          @ast.Value::Long(2L),
          @ast.Value::Long(3L),
        ]),
      )
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: Record all concrete" {
  let e = @ast.Expr::Record([
    ("x", @ast.Expr::Lit(@ast.Literal::Long(1L))),
    ("y", @ast.Expr::Lit(@ast.Literal::String("hi"))),
  ])
  match eval_simple(e) {
    @ast.PartialValue::Value(@ast.Value::Record(map)) =>
      match map.get("x") {
        Some(v) => @debug.assert_eq(true, v == @ast.Value::Long(1L))
        None => @debug.assert_eq(true, false)
      }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: ExtensionApp raises" {
  let e = @ast.Expr::ExtensionApp(@ast.Name::{ ns: ["ip"], name: "parse" }, [
    @ast.Expr::Lit(@ast.Literal::String("127.0.0.1")),
  ])
  let mut raised = false
  try eval_expr(e, empty_req(), empty_store()) |> ignore catch {
    ExtensionNotSupported(_) => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_expr: Slot raises" {
  let e = @ast.Expr::Slot("principal")
  let mut raised = false
  try eval_expr(e, empty_req(), empty_store()) |> ignore catch {
    SlotNotSupported => raised = true
    _ => ()
  }
  @debug.assert_eq(true, raised)
}

///|
test "eval_expr: Unknown returns Residual" {
  let e = @ast.expr_unknown("x")
  match eval_simple(e) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: BinaryApp In hierarchy match" {
  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), ent)]) }
  let e = @ast.Expr::BinaryApp(
    @ast.BinaryOp::In_,
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins"))),
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: GetTag" {
  let tags = Map([("env", @ast.Value::String("prod"))])
  let ent = entity(uid("User", "alice"), Map([]), tags, [])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), ent)]) }
  let e = @ast.Expr::GetTag(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.Expr::Lit(@ast.Literal::String("env")),
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::String("prod"))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: HasTag" {
  let tags = Map([("env", @ast.Value::String("prod"))])
  let ent = entity(uid("User", "alice"), Map([]), tags, [])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), ent)]) }
  let e = @ast.Expr::HasTag(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.Expr::Lit(@ast.Literal::String("env")),
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(true))
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_expr: HasTag missing" {
  let ent = entity(uid("User", "alice"), Map([]), Map([]), [])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), ent)]) }
  let e = @ast.Expr::HasTag(
    @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
    @ast.Expr::Lit(@ast.Literal::String("missing")),
  )
  match eval_expr(e, empty_req(), store) {
    @ast.PartialValue::Value(v) =>
      @debug.assert_eq(true, v == @ast.Value::Bool(false))
    _ => @debug.assert_eq(true, false)
  }
}

// ---------------------------------------------------------------------------
// Policy evaluation tests
// ---------------------------------------------------------------------------

///|
test "eval_policy: scope does not match principal" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::Eq(uid("User", "alice")),
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let req = Request::{
    principal: concrete_uid("User", "bob"),
    action: concrete_uid("Action", "view"),
    resource: concrete_uid("Photo", "x"),
    context: Context::Concrete(@ast.Value::Record(Map([]))),
  }
  @debug.assert_eq(
    true,
    eval_policy(p, req, empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(false)),
  )
}

///|
test "eval_policy: all scopes match no conditions" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let req = empty_req()
  @debug.assert_eq(
    true,
    eval_policy(p, req, empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(true)),
  )
}

///|
test "eval_policy: when condition true" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::Lit(@ast.Literal::Bool(true)),
      },
    ],
  }
  @debug.assert_eq(
    true,
    eval_policy(p, empty_req(), empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(true)),
  )
}

///|
test "eval_policy: when condition false" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::Lit(@ast.Literal::Bool(false)),
      },
    ],
  }
  @debug.assert_eq(
    true,
    eval_policy(p, empty_req(), empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(false)),
  )
}

///|
test "eval_policy: unless condition true" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::Unless,
        body: @ast.Expr::Lit(@ast.Literal::Bool(true)),
      },
    ],
  }
  @debug.assert_eq(
    true,
    eval_policy(p, empty_req(), empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(false)),
  )
}

///|
test "eval_policy: unless condition false" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::Unless,
        body: @ast.Expr::Lit(@ast.Literal::Bool(false)),
      },
    ],
  }
  @debug.assert_eq(
    true,
    eval_policy(p, empty_req(), empty_store()) ==
    @ast.PartialValue::Value(@ast.Value::Bool(true)),
  )
}

///|
test "eval_policy: scope In match" {
  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store = TestStore::{ entities: Map([(uid("User", "alice"), ent)]) }
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::In(uid("Team", "admins")),
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let req = Request::{
    principal: concrete_uid("User", "alice"),
    action: concrete_uid("Action", "view"),
    resource: concrete_uid("Photo", "x"),
    context: Context::Concrete(@ast.Value::Record(Map([]))),
  }
  @debug.assert_eq(
    true,
    eval_policy(p, req, store) ==
    @ast.PartialValue::Value(@ast.Value::Bool(true)),
  )
}

///|
test "eval_policy: residual condition" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.expr_unknown("x"),
      },
    ],
  }
  match eval_policy(p, empty_req(), empty_store()) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_policy: unless residual condition" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::Unless,
        body: @ast.expr_unknown("y"),
      },
    ],
  }
  match eval_policy(p, empty_req(), empty_store()) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "eval_policy: unknown principal produces residual" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::Eq(uid("User", "alice")),
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let req = Request::{
    principal: EntityUIDEntry::Unknown(@ast.EntityType("User")),
    action: concrete_uid("Action", "v"),
    resource: concrete_uid("Photo", "x"),
    context: Context::Concrete(@ast.Value::Record(Map([]))),
  }
  // Principal is unknown → scope check skipped, var lookup produces residual
  match eval_policy(p, req, empty_store()) {
    @ast.PartialValue::Residual(_) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq(true, false)
  }
}
