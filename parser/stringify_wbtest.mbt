// Stringify tests — whitebox inspect tests for Expr and Policy serialization.
// Uses `inspect` snapshot testing (matching json_test.mbt pattern).
// Reference: cedar-go/internal/parser/cedar_marshal_test.go

// ---------------------------------------------------------------------------
// Literals
// ---------------------------------------------------------------------------

///|
test "stringify bool true" {
  let e = @ast.expr_bool(true)
  inspect(stringify_expr(e), content="true")
}

///|
test "stringify bool false" {
  let e = @ast.expr_bool(false)
  inspect(stringify_expr(e), content="false")
}

///|
test "stringify long" {
  let e = @ast.expr_long(42L)
  inspect(stringify_expr(e), content="42")
}

///|
test "stringify long negative" {
  let e = @ast.expr_long(-1L)
  inspect(stringify_expr(e), content="-1")
}

///|
test "stringify string" {
  let e = @ast.expr_str("hello")
  inspect(stringify_expr(e), content="\"hello\"")
}

///|
test "stringify entity uid" {
  let e = @ast.expr_euid("User", "alice")
  inspect(stringify_expr(e), content="User::\"alice\"")
}

///|
test "stringify entity uid namespaced" {
  let e = @ast.expr_euid("Org::User", "alice")
  inspect(stringify_expr(e), content="Org::User::\"alice\"")
}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

///|
test "stringify var principal" {
  inspect(stringify_expr(@ast.expr_principal()), content="principal")
}

///|
test "stringify var action" {
  inspect(stringify_expr(@ast.expr_action()), content="action")
}

///|
test "stringify var resource" {
  inspect(stringify_expr(@ast.expr_resource()), content="resource")
}

///|
test "stringify var context" {
  inspect(stringify_expr(@ast.expr_context()), content="context")
}

// ---------------------------------------------------------------------------
// If-then-else
// ---------------------------------------------------------------------------

///|
test "stringify if then else" {
  let e = @ast.expr_if(
    @ast.expr_bool(true),
    @ast.expr_long(1L),
    @ast.expr_long(2L),
  )
  inspect(stringify_expr(e), content="if true then 1 else 2")
}

///|
test "stringify nested if" {
  let inner = @ast.expr_if(
    @ast.expr_bool(false),
    @ast.expr_long(1L),
    @ast.expr_long(2L),
  )
  let e = @ast.expr_if(@ast.expr_bool(true), inner, @ast.expr_long(3L))
  inspect(
    stringify_expr(e),
    content="if true then if false then 1 else 2 else 3",
  )
}

// ---------------------------------------------------------------------------
// And / Or
// ---------------------------------------------------------------------------

///|
test "stringify and" {
  let e = @ast.expr_bool(true).and_(@ast.expr_bool(false))
  inspect(stringify_expr(e), content="true && false")
}

///|
test "stringify or" {
  let e = @ast.expr_bool(true).or_(@ast.expr_bool(false))
  inspect(stringify_expr(e), content="true || false")
}

///|
test "stringify chained and" {
  let e = @ast.expr_bool(true)
    .and_(@ast.expr_bool(false))
    .and_(@ast.expr_bool(true))
  inspect(stringify_expr(e), content="true && false && true")
}

///|
test "stringify chained or" {
  let e = @ast.expr_bool(true)
    .or_(@ast.expr_bool(false))
    .or_(@ast.expr_bool(true))
  inspect(stringify_expr(e), content="true || false || true")
}

///|
test "stringify and over or precedence" {
  let e = @ast.expr_bool(true)
    .and_(@ast.expr_bool(false))
    .or_(@ast.expr_bool(true).and_(@ast.expr_bool(true)))
  inspect(stringify_expr(e), content="true && false || true && true")
}

// ---------------------------------------------------------------------------
// Arithmetic — addition, subtraction, multiplication
// ---------------------------------------------------------------------------

///|
test "stringify addition" {
  let e = @ast.expr_long(1L).add(@ast.expr_long(2L))
  inspect(stringify_expr(e), content="1 + 2")
}

///|
test "stringify subtraction" {
  let e = @ast.expr_long(3L).sub(@ast.expr_long(1L))
  inspect(stringify_expr(e), content="3 - 1")
}

///|
test "stringify multiplication" {
  let e = @ast.expr_long(2L).mul(@ast.expr_long(3L))
  inspect(stringify_expr(e), content="2 * 3")
}

///|
test "stringify chained addition" {
  let e = @ast.expr_long(1L).add(@ast.expr_long(2L)).add(@ast.expr_long(3L))
  inspect(stringify_expr(e), content="1 + 2 + 3")
}

///|
test "stringify chained multiplication" {
  let e = @ast.expr_long(42L).mul(@ast.expr_long(2L)).mul(@ast.expr_long(1L))
  inspect(stringify_expr(e), content="42 * 2 * 1")
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

///|
test "stringify equal" {
  let e = @ast.expr_long(2L).eq(@ast.expr_long(2L))
  inspect(stringify_expr(e), content="2 == 2")
}

///|
test "stringify not equal" {
  let e = @ast.expr_long(2L).ne(@ast.expr_long(3L))
  inspect(stringify_expr(e), content="2 != 3")
}

///|
test "stringify less than" {
  let e = @ast.expr_long(2L).lt(@ast.expr_long(42L))
  inspect(stringify_expr(e), content="2 < 42")
}

///|
test "stringify less than or equal" {
  let e = @ast.expr_long(2L).le(@ast.expr_long(42L))
  inspect(stringify_expr(e), content="2 <= 42")
}

///|
test "stringify greater than" {
  let e = @ast.expr_long(42L).gt(@ast.expr_long(2L))
  inspect(stringify_expr(e), content="42 > 2")
}

///|
test "stringify greater than or equal" {
  let e = @ast.expr_long(42L).ge(@ast.expr_long(2L))
  inspect(stringify_expr(e), content="42 >= 2")
}

// ---------------------------------------------------------------------------
// Relational — in, has, like, is
// ---------------------------------------------------------------------------

///|
test "stringify in" {
  let e = @ast.expr_principal().in_(@ast.expr_euid("Group", "folkHeroes"))
  inspect(stringify_expr(e), content="principal in Group::\"folkHeroes\"")
}

///|
test "stringify has" {
  let e = @ast.expr_principal().has("firstName")
  inspect(stringify_expr(e), content="principal has firstName")
}

///|
test "stringify has string attribute" {
  let e = @ast.expr_principal().has("1stName")
  inspect(stringify_expr(e), content="principal has \"1stName\"")
}

///|
test "stringify has reserved keyword" {
  let e = @ast.expr_context().has("if")
  inspect(stringify_expr(e), content="context has \"if\"")
}

///|
test "stringify like" {
  let e = @ast.expr_principal()
    .access("firstName")
    .like(@ast.Pattern::{
      elements: [@ast.Char('j'), @ast.Char('o'), @ast.Char('h'), @ast.Char('n')],
    })
  inspect(stringify_expr(e), content="principal.firstName like \"john\"")
}

///|
test "stringify is" {
  let e = @ast.expr_principal().is_(@ast.entity_type("User"))
  inspect(stringify_expr(e), content="principal is User")
}

///|
test "stringify is long path" {
  let e = @ast.expr_principal().is_(@ast.entity_type("X::Y"))
  inspect(stringify_expr(e), content="principal is X::Y")
}

///|
test "stringify is in" {
  let e = @ast.expr_principal().is_in(
    @ast.entity_type("User"),
    @ast.expr_euid("Group", "folkHeroes"),
  )
  inspect(
    stringify_expr(e),
    content="principal is User && principal is User in Group::\"folkHeroes\"",
  )
}

// ---------------------------------------------------------------------------
// Method calls — contains, containsAll, containsAny, getTag, hasTag, isEmpty
// ---------------------------------------------------------------------------

///|
test "stringify contains" {
  let e = @ast.expr_context().access("strings").contains(@ast.expr_str("foo"))
  inspect(stringify_expr(e), content="context.strings.contains(\"foo\")")
}

///|
test "stringify containsAll" {
  let e = @ast.expr_context()
    .access("strings")
    .contains_all(@ast.expr_set([@ast.expr_str("foo")]))
  inspect(stringify_expr(e), content="context.strings.containsAll([\"foo\"])")
}

///|
test "stringify containsAny" {
  let e = @ast.expr_context()
    .access("strings")
    .contains_any(@ast.expr_set([@ast.expr_str("foo")]))
  inspect(stringify_expr(e), content="context.strings.containsAny([\"foo\"])")
}

///|
test "stringify getTag" {
  let e = @ast.expr_principal().get_tag(@ast.expr_str("blue"))
  inspect(stringify_expr(e), content="principal.getTag(\"blue\")")
}

///|
test "stringify hasTag" {
  let e = @ast.expr_principal().has_tag(@ast.expr_str("blue"))
  inspect(stringify_expr(e), content="principal.hasTag(\"blue\")")
}

///|
test "stringify isEmpty" {
  let e = @ast.expr_is_empty(@ast.expr_context().access("strings"))
  inspect(stringify_expr(e), content="context.strings.isEmpty()")
}

// ---------------------------------------------------------------------------
// GetAttr — attribute access
// ---------------------------------------------------------------------------

///|
test "stringify attribute access" {
  let e = @ast.expr_context().access("boolValue")
  inspect(stringify_expr(e), content="context.boolValue")
}

///|
test "stringify chained attribute access" {
  let e = @ast.expr_context().access("foo").access("bar")
  inspect(stringify_expr(e), content="context.foo.bar")
}

///|
test "stringify bracket access reserved keyword" {
  let e = @ast.expr_context().access("true")
  inspect(stringify_expr(e), content="context[\"true\"]")
}

///|
test "stringify bracket access empty string" {
  let e = @ast.expr_context().access("")
  inspect(stringify_expr(e), content="context[\"\"]")
}

// ---------------------------------------------------------------------------
// Set & Record
// ---------------------------------------------------------------------------

///|
test "stringify empty set" {
  let e = @ast.expr_set([])
  inspect(stringify_expr(e), content="[]")
}

///|
test "stringify set with elements" {
  let e = @ast.expr_set([
    @ast.expr_long(1L),
    @ast.expr_long(2L),
    @ast.expr_long(3L),
  ])
  inspect(stringify_expr(e), content="[1, 2, 3]")
}

///|
test "stringify empty record" {
  let e = @ast.expr_record([])
  inspect(stringify_expr(e), content="{}")
}

///|
test "stringify record with pairs" {
  let e = @ast.expr_record([
    ("foo", @ast.expr_long(1L)),
    ("bar", @ast.expr_bool(true)),
  ])
  inspect(stringify_expr(e), content="{foo: 1, bar: true}")
}

///|
test "stringify record with string key" {
  let e = @ast.expr_record([("key", @ast.expr_str("some value"))])
  inspect(stringify_expr(e), content="{key: \"some value\"}")
}

// ---------------------------------------------------------------------------
// Extension calls
// ---------------------------------------------------------------------------

///|
test "stringify extension call no args" {
  let e = @ast.expr_ext_call(@ast.Name::{ ns: [], name: "ip" }, [])
  inspect(stringify_expr(e), content="ip()")
}

///|
test "stringify extension call with arg" {
  let e = @ast.expr_ext_call(@ast.Name::{ ns: [], name: "ip" }, [
    @ast.expr_str("1.2.3.4"),
  ])
  inspect(stringify_expr(e), content="ip(\"1.2.3.4\")")
}

///|
test "stringify extension call decimal" {
  let e = @ast.expr_ext_call(@ast.Name::{ ns: [], name: "decimal" }, [
    @ast.expr_str("12.34"),
  ])
  inspect(stringify_expr(e), content="decimal(\"12.34\")")
}

///|
test "stringify extension call with context" {
  let e = @ast.expr_ext_call(@ast.Name::{ ns: [], name: "ip" }, [
    @ast.expr_context().access("someString"),
  ])
  inspect(stringify_expr(e), content="ip(context.someString)")
}

// ---------------------------------------------------------------------------
// Slot & Unknown
// ---------------------------------------------------------------------------

///|
test "stringify slot" {
  let e = @ast.Slot("principal")
  inspect(stringify_expr(e), content="?principal")
}

///|
test "stringify unknown" {
  let e = @ast.expr_unknown("name")
  inspect(stringify_expr(e), content="name")
}

// ---------------------------------------------------------------------------
// Unary operators
// ---------------------------------------------------------------------------

///|
test "stringify not" {
  let e = @ast.expr_not(@ast.expr_bool(true))
  inspect(stringify_expr(e), content="!true")
}

///|
test "stringify negate" {
  let e = @ast.expr_neg(@ast.expr_long(1L))
  inspect(stringify_expr(e), content="-1")
}

///|
test "stringify double not" {
  let e = @ast.expr_not(@ast.expr_not(@ast.expr_bool(true)))
  inspect(stringify_expr(e), content="!!true")
}

///|
test "stringify not negate" {
  let e = @ast.expr_not(@ast.expr_neg(@ast.expr_long(-1L)))
  inspect(stringify_expr(e), content="!--1")
}

// ---------------------------------------------------------------------------
// Precedence — parentheses where needed
// ---------------------------------------------------------------------------

///|
test "precedence mult over add" {
  let e = @ast.expr_long(2L).mul(@ast.expr_long(3L)).add(@ast.expr_long(4L))
  inspect(stringify_expr(e), content="2 * 3 + 4")
}

///|
test "precedence add under mult" {
  let e = @ast.expr_long(2L).mul(@ast.expr_long(3L).add(@ast.expr_long(4L)))
  inspect(stringify_expr(e), content="2 * (3 + 4)")
}

///|
test "precedence add over rel" {
  let e = @ast.expr_long(1L).add(@ast.expr_long(1L)).lt(@ast.expr_long(3L))
  inspect(stringify_expr(e), content="1 + 1 < 3")
}

///|
test "precedence rel over and" {
  let e = @ast.expr_long(1L).lt(@ast.expr_long(2L)).and_(@ast.expr_bool(true))
  inspect(stringify_expr(e), content="1 < 2 && true")
}

///|
test "precedence and under or" {
  let e = @ast.expr_bool(true).or_(
    @ast.expr_bool(false).and_(@ast.expr_bool(true)),
  )
  inspect(stringify_expr(e), content="true || false && true")
}

///|
test "precedence parens over unary" {
  let e = @ast.expr_neg(@ast.expr_long(2L).add(@ast.expr_long(3L)))
  inspect(stringify_expr(e), content="-(2 + 3)")
}

///|
test "precedence if under and" {
  let e = @ast.expr_bool(true).and_(
    @ast.expr_if(@ast.expr_bool(true), @ast.expr_long(1L), @ast.expr_long(2L)),
  )
  inspect(stringify_expr(e), content="true && (if true then 1 else 2)")
}

// ---------------------------------------------------------------------------
// Policy — basic
// ---------------------------------------------------------------------------

///|
test "stringify policy permit all" {
  let p = @ast.default().with_id("policy").permit()
  inspect(stringify(p), content="permit(principal, action, resource);")
}

///|
test "stringify policy forbid all" {
  let p = @ast.default().with_id("policy").forbid()
  inspect(stringify(p), content="forbid(principal, action, resource);")
}

///|
test "stringify policy without id" {
  let p = @ast.default().permit()
  inspect(stringify(p), content="permit(principal, action, resource);")
}

// ---------------------------------------------------------------------------
// Policy — scope constraints
// ---------------------------------------------------------------------------

///|
test "stringify policy scope eq" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .principal_eq("User", "alice")
    .action_eq("PhotoOp", "view")
    .resource_eq("Photo", "VacationPhoto94.jpg")
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal == User::"alice",
      #|  action == PhotoOp::"view",
      #|  resource == Photo::"VacationPhoto94.jpg"
      #|);
    ),
  )
}

///|
test "stringify policy scope in" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .principal_in("Team", "admins")
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal in Team::"admins",
      #|  action,
      #|  resource
      #|);
    ),
  )
}

///|
test "stringify policy scope is" {
  let p = @ast.default().with_id("policy").permit().principal_is("User")
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal is User,
      #|  action,
      #|  resource
      #|);
    ),
  )
}

///|
test "stringify policy scope is in" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .principal_is_in("User", "Org", "corp")
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal is User in Org::"corp",
      #|  action,
      #|  resource
      #|);
    ),
  )
}

///|
test "stringify policy scope action in set" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .action_in_set([("Action", "read"), ("Action", "write")])
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal,
      #|  action in [Action::"read", Action::"write"],
      #|  resource
      #|);
    ),
  )
}

///|
test "stringify policy mixed scopes" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .principal_eq("User", "alice")
    .action_in("PhotoOp", "view")
  inspect(
    stringify(p),
    content=(
      #|permit(
      #|  principal == User::"alice",
      #|  action in PhotoOp::"view",
      #|  resource
      #|);
    ),
  )
}

// ---------------------------------------------------------------------------
// Policy — conditions
// ---------------------------------------------------------------------------

///|
test "stringify policy when condition" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.expr_resource().has("public"))
  inspect(
    stringify(p),
    content=(
      #|permit(principal, action, resource)
      #|when { resource has public };
    ),
  )
}

///|
test "stringify policy unless condition" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .unless(@ast.expr_bool(false))
  inspect(
    stringify(p),
    content=(
      #|permit(principal, action, resource)
      #|unless { false };
    ),
  )
}

///|
test "stringify policy when and unless" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.expr_bool(true))
    .unless(@ast.expr_bool(false))
  inspect(
    stringify(p),
    content=(
      #|permit(principal, action, resource)
      #|when { true }
      #|unless { false };
    ),
  )
}

///|
test "stringify policy complex condition" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .when_(
      @ast.expr_resource()
      .access("foo")
      .has("bar")
      .and_(@ast.expr_resource().access("isIpv4").eq(@ast.expr_str("ipv4"))),
    )
  inspect(
    stringify(p),
    content=(
      #|permit(principal, action, resource)
      #|when { resource.foo has bar && resource.isIpv4 == "ipv4" };
    ),
  )
}

// ---------------------------------------------------------------------------
// Policy — annotations
// ---------------------------------------------------------------------------

///|
test "stringify policy annotation" {
  let p = @ast.default().with_id("policy").permit().annotate("foo", "bar")
  inspect(
    stringify(p),
    content=(
      #|@foo("bar")
      #|permit(principal, action, resource);
    ),
  )
}

///|
test "stringify policy bare annotation" {
  let p = @ast.default().with_id("policy").permit().annotate("foo", "")
  inspect(
    stringify(p),
    content=(
      #|@foo
      #|permit(principal, action, resource);
    ),
  )
}

///|
test "stringify policy multiple annotations" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .annotate("foo", "bar")
    .annotate("baz", "quux")
  inspect(
    stringify(p),
    content=(
      #|@foo("bar")
      #|@baz("quux")
      #|permit(principal, action, resource);
    ),
  )
}

///|
test "stringify policy annotation with conditions" {
  let p = @ast.default()
    .with_id("policy")
    .permit()
    .annotate("source", "admin")
    .when_(@ast.expr_bool(true))
  inspect(
    stringify(p),
    content=(
      #|@source("admin")
      #|permit(principal, action, resource)
      #|when { true };
    ),
  )
}

// ---------------------------------------------------------------------------
// Policy — multiline scopes
// ---------------------------------------------------------------------------

///|
test "stringify policy all scope single line" {
  let p = @ast.default().with_id("policy").permit()
  inspect(stringify(p), content="permit(principal, action, resource);")
}

///|
test "stringify policy forbid scope single line" {
  let p = @ast.default().with_id("policy").forbid()
  inspect(stringify(p), content="forbid(principal, action, resource);")
}

// ---------------------------------------------------------------------------
// Chained has
// ---------------------------------------------------------------------------

///|
test "stringify chained has" {
  let pa = @ast.expr_principal()
  let e = pa
    .has("a")
    .and_(pa.access("a").has("b").and_(pa.access("a").access("b").has("c")))
  inspect(
    stringify_expr(e),
    content="principal has a && (principal.a has b && principal.a.b has c)",
  )
}
