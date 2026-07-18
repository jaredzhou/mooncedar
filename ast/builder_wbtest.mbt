// Builder tests — whitebox tests for expr builder and policy builder.
// References: the plan doc for builder pattern

// ---------------------------------------------------------------------------
// Expr leaf constructors
// ---------------------------------------------------------------------------

///|
test "val_bool" {
  @debug.assert_eq(expr_bool(true), Lit(Bool(true)))
  @debug.assert_eq(expr_bool(false), Lit(Bool(false)))
}

///|
test "val_long" {
  @debug.assert_eq(expr_long(42L), Lit(Long(42L)))
  @debug.assert_eq(expr_long(0L), Lit(Long(0L)))
}

///|
test "val_str" {
  @debug.assert_eq(expr_str("hello"), Lit(String("hello")))
  @debug.assert_eq(expr_str(""), Lit(String("")))
}

///|
test "val_euid" {
  @debug.assert_eq(
    expr_euid("User", "alice"),
    Lit(EntityUID(EntityUID::{ type_: "User", id: "alice" })),
  )
}

///|
test "var_principal" {
  @debug.assert_eq(expr_principal(), Var(Principal))
}

///|
test "var_action" {
  @debug.assert_eq(expr_action(), Var(Action))
}

///|
test "var_resource" {
  @debug.assert_eq(expr_resource(), Var(Resource))
}

///|
test "var_context" {
  @debug.assert_eq(expr_context(), Var(Context))
}

// ---------------------------------------------------------------------------
// Expr non-chaining constructors
// ---------------------------------------------------------------------------

///|
test "if_" {
  let cond = expr_bool(true)
  let t = expr_str("yes")
  let e = expr_str("no")
  @debug.assert_eq(expr_if(cond, t, e), If(cond, t, e))
}

///|
test "not_" {
  @debug.assert_eq(expr_not(expr_bool(true)), UnaryApp(Not, Lit(Bool(true))))
}

///|
test "neg" {
  @debug.assert_eq(expr_neg(expr_long(1L)), UnaryApp(Neg, Lit(Long(1L))))
}

///|
test "is_empty" {
  @debug.assert_eq(
    expr_is_empty(expr_str("x")),
    UnaryApp(IsEmpty, Lit(String("x"))),
  )
}

///|
test "set_" {
  let elems = [expr_bool(true), expr_str("a")]
  @debug.assert_eq(expr_set(elems), Set(elems))
  @debug.assert_eq(expr_set([]), Set([]))
}

///|
test "record_" {
  let pairs : Array[(String, Expr)] = [
    ("a", expr_long(1L)),
    ("b", expr_str("x")),
  ]
  @debug.assert_eq(expr_record(pairs), Record(pairs))
}

///|
test "ext_call" {
  let name = Name::{ ns: ["ip"], name: "is_ipv4" }
  let arg = expr_str("1.2.3.4")
  @debug.assert_eq(expr_ext_call(name, [arg]), ExtensionApp(name, [arg]))
}

// ---------------------------------------------------------------------------
// Expr chaining methods — binary operators
// ---------------------------------------------------------------------------

///|
test "eq" {
  let lhs = expr_principal()
  let rhs = expr_str("alice")
  @debug.assert_eq(
    lhs.eq(rhs),
    BinaryApp(Eq, Var(Principal), Lit(String("alice"))),
  )
}

///|
test "ne" {
  let lhs = expr_principal()
  let rhs = expr_str("alice")
  @debug.assert_eq(
    lhs.ne(rhs),
    BinaryApp(Ne, Var(Principal), Lit(String("alice"))),
  )
}

///|
test "lt" {
  let lhs = expr_long(3L)
  let rhs = expr_long(5L)
  @debug.assert_eq(lhs.lt(rhs), BinaryApp(Less, Lit(Long(3L)), Lit(Long(5L))))
}

///|
test "le" {
  let lhs = expr_long(3L)
  let rhs = expr_long(5L)
  @debug.assert_eq(lhs.le(rhs), BinaryApp(LessEq, Lit(Long(3L)), Lit(Long(5L))))
}

///|
test "gt" {
  let lhs = expr_long(5L)
  let rhs = expr_long(3L)
  @debug.assert_eq(lhs.gt(rhs), BinaryApp(Gt, Lit(Long(5L)), Lit(Long(3L))))
}

///|
test "ge" {
  let lhs = expr_long(5L)
  let rhs = expr_long(3L)
  @debug.assert_eq(lhs.ge(rhs), BinaryApp(Ge, Lit(Long(5L)), Lit(Long(3L))))
}

///|
test "add" {
  let lhs = expr_long(1L)
  let rhs = expr_long(2L)
  @debug.assert_eq(lhs.add(rhs), BinaryApp(Add, Lit(Long(1L)), Lit(Long(2L))))
}

///|
test "sub" {
  let lhs = expr_long(5L)
  let rhs = expr_long(3L)
  @debug.assert_eq(lhs.sub(rhs), BinaryApp(Sub, Lit(Long(5L)), Lit(Long(3L))))
}

///|
test "mul" {
  let lhs = expr_long(2L)
  let rhs = expr_long(3L)
  @debug.assert_eq(lhs.mul(rhs), BinaryApp(Mul, Lit(Long(2L)), Lit(Long(3L))))
}

// ---------------------------------------------------------------------------
// Expr chaining methods — logical / set operators
// ---------------------------------------------------------------------------

///|
test "and_" {
  let lhs = expr_bool(true)
  let rhs = expr_bool(false)
  @debug.assert_eq(lhs.and_(rhs), And(Lit(Bool(true)), Lit(Bool(false))))
}

///|
test "or_" {
  let lhs = expr_bool(true)
  let rhs = expr_bool(false)
  @debug.assert_eq(lhs.or_(rhs), Or(Lit(Bool(true)), Lit(Bool(false))))
}

///|
test "in_" {
  let entity = expr_euid("Photo", "sunset")
  let parent = expr_euid("Album", "vacation")
  @debug.assert_eq(
    entity.in_(parent),
    BinaryApp(
      In_,
      Lit(EntityUID(EntityUID::{ type_: "Photo", id: "sunset" })),
      Lit(EntityUID(EntityUID::{ type_: "Album", id: "vacation" })),
    ),
  )
}

///|
test "contains" {
  let set_expr = expr_set([expr_str("a")])
  let elem = expr_str("a")
  @debug.assert_eq(
    set_expr.contains(elem),
    BinaryApp(Contains, Set([Lit(String("a"))]), Lit(String("a"))),
  )
}

///|
test "contains_all" {
  let set_expr = expr_set([expr_str("a"), expr_str("b")])
  let subset = expr_set([expr_str("a")])
  @debug.assert_eq(
    set_expr.contains_all(subset),
    BinaryApp(
      ContainsAll,
      Set([Lit(String("a")), Lit(String("b"))]),
      Set([Lit(String("a"))]),
    ),
  )
}

///|
test "contains_any" {
  let set_expr = expr_set([expr_str("a")])
  let other = expr_set([expr_str("a"), expr_str("b")])
  @debug.assert_eq(
    set_expr.contains_any(other),
    BinaryApp(
      ContainsAny,
      Set([Lit(String("a"))]),
      Set([Lit(String("a")), Lit(String("b"))]),
    ),
  )
}

///|
test "get_tag" {
  let entity = expr_euid("User", "alice")
  let tag = expr_str("department")
  @debug.assert_eq(
    entity.get_tag(tag),
    GetTag(
      Lit(EntityUID(EntityUID::{ type_: "User", id: "alice" })),
      Lit(String("department")),
    ),
  )
}

///|
test "has_tag" {
  let entity = expr_euid("User", "alice")
  let tag = expr_str("department")
  @debug.assert_eq(
    entity.has_tag(tag),
    HasTag(
      Lit(EntityUID(EntityUID::{ type_: "User", id: "alice" })),
      Lit(String("department")),
    ),
  )
}

// ---------------------------------------------------------------------------
// Expr chaining methods — attribute access, type test, pattern
// ---------------------------------------------------------------------------

///|
test "access" {
  let entity = expr_principal()
  @debug.assert_eq(entity.access("dept"), GetAttr(Var(Principal), "dept"))
}

///|
test "has" {
  let entity = expr_principal()
  @debug.assert_eq(entity.has("dept"), HasAttr(Var(Principal), "dept"))
}

///|
test "like" {
  let s = expr_str("hello")
  let pat = Pattern::{ elements: [Char('h'), Wildcard] }
  @debug.assert_eq(s.like(pat), Like(Lit(String("hello")), pat))
}

///|
test "is_" {
  let entity = expr_principal()
  @debug.assert_eq(
    entity.is_(EntityType("User")),
    Expr::Is(Var(Principal), EntityType("User")),
  )
}

///|
test "is_in" {
  let entity = expr_principal()
  let ty = EntityType("User")
  let parent = expr_euid("Org", "corp")
  let is_expr = Expr::Is(Var(Principal), EntityType("User"))
  @debug.assert_eq(
    entity.is_in(ty, parent),
    And(
      is_expr,
      BinaryApp(
        In_,
        is_expr,
        Lit(EntityUID(EntityUID::{ type_: "Org", id: "corp" })),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Expr chaining combinations
// ---------------------------------------------------------------------------

///|
test "chaining: principal.dept == 'engineering'" {
  let expr = expr_principal().access("dept").eq(expr_str("engineering"))
  @debug.assert_eq(
    expr,
    BinaryApp(Eq, GetAttr(Var(Principal), "dept"), Lit(String("engineering"))),
  )
}

///|
test "chaining: principal.dept == 'engineering' && resource.public == true" {
  let expr = expr_principal()
    .access("dept")
    .eq(expr_str("engineering"))
    .and_(expr_resource().access("public").eq(expr_bool(true)))
  @debug.assert_eq(
    expr,
    And(
      BinaryApp(Eq, GetAttr(Var(Principal), "dept"), Lit(String("engineering"))),
      BinaryApp(Eq, GetAttr(Var(Resource), "public"), Lit(Bool(true))),
    ),
  )
}

///|
test "chaining: expr_not(principal.age.lt(18))" {
  let expr = expr_not(expr_principal().access("age").lt(expr_long(18L)))
  @debug.assert_eq(
    expr,
    UnaryApp(
      Not,
      BinaryApp(Less, GetAttr(Var(Principal), "age"), Lit(Long(18L))),
    ),
  )
}

///|
test "chaining: resource.tags.contains_all(set_)" {
  let expr = expr_resource()
    .access("tags")
    .contains_all(expr_set([expr_str("public"), expr_str("verified")]))
  @debug.assert_eq(
    expr,
    BinaryApp(
      ContainsAll,
      GetAttr(Var(Resource), "tags"),
      Set([Lit(String("public")), Lit(String("verified"))]),
    ),
  )
}

// ---------------------------------------------------------------------------
// Policy default
// ---------------------------------------------------------------------------

///|
test "default policy" {
  let p = default()
  @debug.assert_eq(p.id, "")
  @debug.assert_eq(p.effect, Permit)
  @debug.assert_eq(p.annotations, [])
  @debug.assert_eq(p.principal, All)
  @debug.assert_eq(p.action, All)
  @debug.assert_eq(p.resource, All)
  @debug.assert_eq(p.conditions, [])
}

// ---------------------------------------------------------------------------
// Policy effect
// ---------------------------------------------------------------------------

///|
test "policy permit" {
  let p = default().forbid().permit()
  @debug.assert_eq(p.effect, Permit)
  @debug.assert_eq(p.principal, All)
}

///|
test "policy forbid" {
  let p = default().forbid()
  @debug.assert_eq(p.effect, Forbid)
}

// ---------------------------------------------------------------------------
// Policy scope — principal
// ---------------------------------------------------------------------------

///|
test "policy principal_eq" {
  let p = default().principal_eq("User", "alice")
  @debug.assert_eq(p.principal, Eq(EntityUID::{ type_: "User", id: "alice" }))
}

///|
test "policy principal_in" {
  let p = default().principal_in("User", "alice")
  @debug.assert_eq(p.principal, In(EntityUID::{ type_: "User", id: "alice" }))
}

///|
test "policy principal_is" {
  let p = default().principal_is("User")
  @debug.assert_eq(p.principal, Is(EntityType("User")))
}

///|
test "policy principal_is_in" {
  let p = default().principal_is_in("User", "Org", "corp")
  @debug.assert_eq(
    p.principal,
    IsIn(EntityType("User"), EntityUID::{ type_: "Org", id: "corp" }),
  )
}

// ---------------------------------------------------------------------------
// Policy scope — action
// ---------------------------------------------------------------------------

///|
test "policy action_eq" {
  let p = default().action_eq("PhotoOp", "view")
  @debug.assert_eq(p.action, Eq(EntityUID::{ type_: "PhotoOp", id: "view" }))
}

///|
test "policy action_in" {
  let p = default().action_in("PhotoOp", "view")
  @debug.assert_eq(p.action, In(EntityUID::{ type_: "PhotoOp", id: "view" }))
}

///|
test "policy action_in_set" {
  let p = default().action_in_set([("PhotoOp", "view"), ("PhotoOp", "delete")])
  @debug.assert_eq(
    p.action,
    InSet([
      EntityUID::{ type_: "PhotoOp", id: "view" },
      EntityUID::{ type_: "PhotoOp", id: "delete" },
    ]),
  )
}

// ---------------------------------------------------------------------------
// Policy scope — resource
// ---------------------------------------------------------------------------

///|
test "policy resource_eq" {
  let p = default().resource_eq("Photo", "sunset.jpg")
  @debug.assert_eq(
    p.resource,
    Eq(EntityUID::{ type_: "Photo", id: "sunset.jpg" }),
  )
}

///|
test "policy resource_in" {
  let p = default().resource_in("Photo", "sunset.jpg")
  @debug.assert_eq(
    p.resource,
    In(EntityUID::{ type_: "Photo", id: "sunset.jpg" }),
  )
}

///|
test "policy resource_is" {
  let p = default().resource_is("Photo")
  @debug.assert_eq(p.resource, Is(EntityType("Photo")))
}

///|
test "policy resource_is_in" {
  let p = default().resource_is_in("Photo", "Album", "vacation")
  @debug.assert_eq(
    p.resource,
    IsIn(EntityType("Photo"), EntityUID::{ type_: "Album", id: "vacation" }),
  )
}

// ---------------------------------------------------------------------------
// Policy metadata
// ---------------------------------------------------------------------------

///|
test "policy with_id" {
  let p = default().with_id("allow-alice")
  @debug.assert_eq(p.id, "allow-alice")
}

///|
test "policy annotate" {
  let p = default().annotate("source", "admin").annotate("priority", "high")
  @debug.assert_eq(p.annotations, [
    Annotation::{ key: "source", value: "admin" },
    Annotation::{ key: "priority", value: "high" },
  ])
}

// ---------------------------------------------------------------------------
// Policy conditions
// ---------------------------------------------------------------------------

///|
test "policy when_" {
  let body = expr_resource().access("public").eq(expr_bool(true))
  let p = default().when_(body)
  @debug.assert_eq(p.conditions, [Condition::{ kind: When, body }])
}

///|
test "policy unless" {
  let body = expr_principal().access("banned").eq(expr_bool(true))
  let p = default().unless(body)
  @debug.assert_eq(p.conditions, [Condition::{ kind: Unless, body }])
}

///|
test "policy multiple conditions" {
  let when_body = expr_resource().access("public").eq(expr_bool(true))
  let unless_body = expr_principal().access("banned").eq(expr_bool(true))
  let p = default().when_(when_body).unless(unless_body)
  @debug.assert_eq(p.conditions.length(), 2)
  @debug.assert_eq(p.conditions[0].kind, When)
  @debug.assert_eq(p.conditions[1].kind, Unless)
}

// ---------------------------------------------------------------------------
// Policy method chaining
// ---------------------------------------------------------------------------

///|
test "chaining: full policy builder" {
  let p = default()
    .with_id("allow-alice")
    .permit()
    .principal_eq("User", "alice")
    .action_in("PhotoOp", "view")
    .resource_is("Photo")
    .when_(expr_resource().access("public").eq(expr_bool(true)))
    .annotate("source", "policy_generator")
  @debug.assert_eq(p.id, "allow-alice")
  @debug.assert_eq(p.effect, Permit)
  @debug.assert_eq(p.principal, Eq(EntityUID::{ type_: "User", id: "alice" }))
  @debug.assert_eq(p.action, In(EntityUID::{ type_: "PhotoOp", id: "view" }))
  @debug.assert_eq(p.resource, Is(EntityType("Photo")))
  @debug.assert_eq(p.conditions.length(), 1)
  @debug.assert_eq(p.annotations.length(), 1)
}

///|
test "chaining: forbid policy with unless" {
  let p = default()
    .forbid()
    .with_id("deny-banned")
    .principal_is("User")
    .action_eq("PhotoOp", "delete")
    .resource_eq("Photo", "secret.png")
    .unless(expr_principal().access("banned").eq(expr_bool(true)))
  @debug.assert_eq(p.effect, Forbid)
  @debug.assert_eq(p.id, "deny-banned")
  @debug.assert_eq(p.principal, Is(EntityType("User")))
  @debug.assert_eq(p.action, Eq(EntityUID::{ type_: "PhotoOp", id: "delete" }))
  @debug.assert_eq(
    p.resource,
    Eq(EntityUID::{ type_: "Photo", id: "secret.png" }),
  )
  @debug.assert_eq(p.conditions.length(), 1)
  @debug.assert_eq(p.conditions[0].kind, Unless)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
test "entity_uid helper" {
  @debug.assert_eq(entity_uid("User", "alice"), EntityUID::{
    type_: "User",
    id: "alice",
  })
}

///|
test "entity_type helper" {
  @debug.assert_eq(entity_type("Photo"), EntityType("Photo"))
}
