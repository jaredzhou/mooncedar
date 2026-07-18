// Expression parser tests — whitebox tests covering all Cedar expression forms.
// References: cedar-go/internal/parser/cedar_parse_test.go
//             cedar-go/internal/parser/cedar_unmarshal_test.go

// ---------------------------------------------------------------------------
// Helper — parse a single expression from source text
// ---------------------------------------------------------------------------

///|
fn parse_expr_src(src : String) -> @ast.Expr raise ParseError {
  let tokens = tokenize(src)
  let (expr, _) = parse_expr(tokens[:])
  expr
}

// ---------------------------------------------------------------------------
// Atoms — literals, variables, entity UIDs, extension functions
// ---------------------------------------------------------------------------

///|
test "parse int literal" {
  let expr = parse_expr_src("42")
  @debug.assert_eq(expr, @ast.Lit(@ast.Long(42L)))
}

///|
test "parse string literal" {
  let expr = parse_expr_src("\"hello\"")
  @debug.assert_eq(expr, @ast.Lit(@ast.String("hello")))
}

///|
test "parse bool literal true" {
  let expr = parse_expr_src("true")
  @debug.assert_eq(expr, @ast.Lit(@ast.Bool(true)))
}

///|
test "parse bool literal false" {
  let expr = parse_expr_src("false")
  @debug.assert_eq(expr, @ast.Lit(@ast.Bool(false)))
}

///|
test "parse variable principal" {
  let expr = parse_expr_src("principal")
  @debug.assert_eq(expr, @ast.Var(@ast.Principal))
}

///|
test "parse variable action" {
  let expr = parse_expr_src("action")
  @debug.assert_eq(expr, @ast.Var(@ast.Action))
}

///|
test "parse variable resource" {
  let expr = parse_expr_src("resource")
  @debug.assert_eq(expr, @ast.Var(@ast.Resource))
}

///|
test "parse variable context" {
  let expr = parse_expr_src("context")
  @debug.assert_eq(expr, @ast.Var(@ast.Context))
}

///|
test "parse entity uid" {
  let expr = parse_expr_src("User::\"alice\"")
  @debug.assert_eq(
    expr,
    @ast.Lit(@ast.EntityUID({ type_: "User", id: "alice" })),
  )
}

///|
test "parse namespaced entity uid" {
  let expr = parse_expr_src("Org::User::\"alice\"")
  @debug.assert_eq(
    expr,
    @ast.Lit(@ast.EntityUID({ type_: "Org::User", id: "alice" })),
  )
}

///|
test "parse extension function no args" {
  let expr = parse_expr_src("ip()")
  @debug.assert_eq(expr, @ast.ExtensionApp({ ns: [], name: "ip" }, []))
}

///|
test "parse extension function with arg" {
  let expr = parse_expr_src("ip(\"1.2.3.4\")")
  @debug.assert_eq(
    expr,
    @ast.ExtensionApp({ ns: [], name: "ip" }, [@ast.Lit(@ast.String("1.2.3.4"))]),
  )
}

///|
test "parse extension function decimal" {
  let expr = parse_expr_src("decimal(\"12.34\")")
  @debug.assert_eq(
    expr,
    @ast.ExtensionApp({ ns: [], name: "decimal" }, [
      @ast.Lit(@ast.String("12.34")),
    ]),
  )
}

///|
test "parse extension function with context arg" {
  let expr = parse_expr_src("ip(context.someString)")
  @debug.assert_eq(
    expr,
    @ast.ExtensionApp({ ns: [], name: "ip" }, [
      @ast.GetAttr(@ast.Var(@ast.Context), "someString"),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Sets & Records
// ---------------------------------------------------------------------------

///|
test "parse empty set" {
  let expr = parse_expr_src("[]")
  @debug.assert_eq(expr, @ast.Set([]))
}

///|
test "parse singleton set" {
  let expr = parse_expr_src("[true]")
  @debug.assert_eq(expr, @ast.Set([@ast.Lit(@ast.Bool(true))]))
}

///|
test "parse set with multiple elements" {
  let expr = parse_expr_src("[1, 2, 3]")
  @debug.assert_eq(
    expr,
    @ast.Set([
      @ast.Lit(@ast.Long(1L)),
      @ast.Lit(@ast.Long(2L)),
      @ast.Lit(@ast.Long(3L)),
    ]),
  )
}

///|
test "parse empty record" {
  let expr = parse_expr_src("{}")
  @debug.assert_eq(expr, @ast.Record([]))
}

///|
test "parse record with string key" {
  let expr = parse_expr_src("{\"key\": \"some value\"}")
  @debug.assert_eq(
    expr,
    @ast.Record([("key", @ast.Lit(@ast.String("some value")))]),
  )
}

///|
test "parse record with ident key" {
  let expr = parse_expr_src("{foo: 1, bar: true}")
  @debug.assert_eq(
    expr,
    @ast.Record([
      ("foo", @ast.Lit(@ast.Long(1L))),
      ("bar", @ast.Lit(@ast.Bool(true))),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Unary operators (Not, Neg)
// ---------------------------------------------------------------------------

///|
test "parse not operator" {
  let expr = parse_expr_src("!true")
  @debug.assert_eq(expr, @ast.UnaryApp(@ast.Not, @ast.Lit(@ast.Bool(true))))
}

///|
test "parse double not" {
  let expr = parse_expr_src("!!true")
  @debug.assert_eq(
    expr,
    @ast.UnaryApp(@ast.Not, @ast.UnaryApp(@ast.Not, @ast.Lit(@ast.Bool(true)))),
  )
}

///|
test "parse negate operator on literal" {
  let expr = parse_expr_src("-1")
  @debug.assert_eq(expr, @ast.Lit(@ast.Long(-1L)))
}

///|
test "parse negate on context" {
  let expr = parse_expr_src("-context")
  @debug.assert_eq(expr, @ast.UnaryApp(@ast.Neg, @ast.Var(@ast.Context)))
}

///|
test "parse chained not negate long" {
  let expr = parse_expr_src("!--1")
  @debug.assert_eq(
    expr,
    @ast.UnaryApp(@ast.Not, @ast.UnaryApp(@ast.Neg, @ast.Lit(@ast.Long(-1L)))),
  )
}

///|
test "parse double negate" {
  let expr = parse_expr_src("--1")
  // --1: first - (Unary Neg) of -1 (Lit Long(-1))
  @debug.assert_eq(expr, @ast.UnaryApp(@ast.Neg, @ast.Lit(@ast.Long(-1L))))
}

// ---------------------------------------------------------------------------
// Binary operators — arithmetic
// ---------------------------------------------------------------------------

///|
test "parse multiplication" {
  let expr = parse_expr_src("42 * 2")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Mul, @ast.Lit(@ast.Long(42L)), @ast.Lit(@ast.Long(2L))),
  )
}

///|
test "parse addition" {
  let expr = parse_expr_src("42 + 2")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Add, @ast.Lit(@ast.Long(42L)), @ast.Lit(@ast.Long(2L))),
  )
}

///|
test "parse subtraction" {
  let expr = parse_expr_src("42 - 2")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Sub, @ast.Lit(@ast.Long(42L)), @ast.Lit(@ast.Long(2L))),
  )
}

///|
test "parse chained multiplication" {
  let expr = parse_expr_src("42 * 2 * 1")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.Mul,
      @ast.BinaryApp(
        @ast.Mul,
        @ast.Lit(@ast.Long(42L)),
        @ast.Lit(@ast.Long(2L)),
      ),
      @ast.Lit(@ast.Long(1L)),
    ),
  )
}

///|
test "parse mixed addition and subtraction" {
  let expr = parse_expr_src("42 - 2 + 1")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.Add,
      @ast.BinaryApp(
        @ast.Sub,
        @ast.Lit(@ast.Long(42L)),
        @ast.Lit(@ast.Long(2L)),
      ),
      @ast.Lit(@ast.Long(1L)),
    ),
  )
}

// ---------------------------------------------------------------------------
// Binary operators — comparison
// ---------------------------------------------------------------------------

///|
test "parse less than" {
  let expr = parse_expr_src("2 < 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Less, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(42L))),
  )
}

///|
test "parse less than or equal" {
  let expr = parse_expr_src("2 <= 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.LessEq,
      @ast.Lit(@ast.Long(2L)),
      @ast.Lit(@ast.Long(42L)),
    ),
  )
}

///|
test "parse greater than" {
  let expr = parse_expr_src("2 > 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Gt, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(42L))),
  )
}

///|
test "parse greater than or equal" {
  let expr = parse_expr_src("2 >= 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Ge, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(42L))),
  )
}

///|
test "parse equal" {
  let expr = parse_expr_src("2 == 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Eq, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(42L))),
  )
}

///|
test "parse not equal" {
  let expr = parse_expr_src("2 != 42")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Ne, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(42L))),
  )
}

// ---------------------------------------------------------------------------
// Binary operators — logical
// ---------------------------------------------------------------------------

///|
test "parse and" {
  let expr = parse_expr_src("true && false")
  @debug.assert_eq(
    expr,
    @ast.And(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(false))),
  )
}

///|
test "parse or" {
  let expr = parse_expr_src("true || false")
  @debug.assert_eq(
    expr,
    @ast.Or(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(false))),
  )
}

///|
test "parse chained and" {
  let expr = parse_expr_src("true && false && true")
  @debug.assert_eq(
    expr,
    @ast.And(
      @ast.And(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(false))),
      @ast.Lit(@ast.Bool(true)),
    ),
  )
}

///|
test "parse chained or" {
  let expr = parse_expr_src("true || false || true")
  @debug.assert_eq(
    expr,
    @ast.Or(
      @ast.Or(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(false))),
      @ast.Lit(@ast.Bool(true)),
    ),
  )
}

///|
test "parse in operator" {
  let expr = parse_expr_src("principal in Group::\"folkHeroes\"")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.In_,
      @ast.Var(@ast.Principal),
      @ast.Lit(@ast.EntityUID({ type_: "Group", id: "folkHeroes" })),
    ),
  )
}

// ---------------------------------------------------------------------------
// Special ops — has, like, is
// ---------------------------------------------------------------------------

///|
test "parse has ident" {
  let expr = parse_expr_src("principal has firstName")
  @debug.assert_eq(expr, @ast.HasAttr(@ast.Var(@ast.Principal), "firstName"))
}

///|
test "parse has string" {
  let expr = parse_expr_src("principal has \"1stName\"")
  @debug.assert_eq(expr, @ast.HasAttr(@ast.Var(@ast.Principal), "1stName"))
}

///|
test "parse like no wildcards" {
  let expr = parse_expr_src("principal.firstName like \"johnny\"")
  @debug.assert_eq(
    expr,
    @ast.Like(@ast.GetAttr(@ast.Var(@ast.Principal), "firstName"), {
      elements: [
        @ast.Char('j'),
        @ast.Char('o'),
        @ast.Char('h'),
        @ast.Char('n'),
        @ast.Char('n'),
        @ast.Char('y'),
      ],
    }),
  )
}

///|
test "parse like wildcard" {
  let expr = parse_expr_src("principal.firstName like \"*\"")
  @debug.assert_eq(
    expr,
    @ast.Like(@ast.GetAttr(@ast.Var(@ast.Principal), "firstName"), {
      elements: [@ast.Wildcard],
    }),
  )
}

///|
test "parse like escaped asterisk" {
  let expr = parse_expr_src("principal.firstName like \"joh\\*nny\"")
  @debug.assert_eq(
    expr,
    @ast.Like(@ast.GetAttr(@ast.Var(@ast.Principal), "firstName"), {
      elements: [
        @ast.Char('j'),
        @ast.Char('o'),
        @ast.Char('h'),
        @ast.Char('*'),
        @ast.Char('n'),
        @ast.Char('n'),
        @ast.Char('y'),
      ],
    }),
  )
}

///|
test "parse like foo like foo" {
  let expr = parse_expr_src("\"f*o\" like \"f\\*o\"")
  @debug.assert_eq(
    expr,
    @ast.Like(@ast.Lit(@ast.String("f*o")), {
      elements: [@ast.Char('f'), @ast.Char('*'), @ast.Char('o')],
    }),
  )
}

///|
test "parse is expression" {
  let expr = parse_expr_src("principal is User")
  @debug.assert_eq(
    expr,
    @ast.Is(@ast.Var(@ast.Principal), @ast.EntityType("User")),
  )
}

///|
test "parse is long path" {
  let expr = parse_expr_src("principal is X::Y")
  @debug.assert_eq(
    expr,
    @ast.Is(@ast.Var(@ast.Principal), @ast.EntityType("X::Y")),
  )
}

///|
test "parse is in" {
  let expr = parse_expr_src("principal is User in Group::\"folkHeroes\"")
  let is_expr = @ast.Expr::Is(@ast.Var(@ast.Principal), @ast.EntityType("User"))
  @debug.assert_eq(
    expr,
    @ast.And(
      is_expr,
      @ast.BinaryApp(
        @ast.In_,
        is_expr,
        @ast.Lit(@ast.EntityUID({ type_: "Group", id: "folkHeroes" })),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Postfix — attribute access, bracket access, method calls
// ---------------------------------------------------------------------------

///|
test "parse attribute access" {
  let expr = parse_expr_src("context.boolValue")
  @debug.assert_eq(expr, @ast.GetAttr(@ast.Var(@ast.Context), "boolValue"))
}

///|
test "parse chained attribute access" {
  let expr = parse_expr_src("context.foo.bar")
  @debug.assert_eq(
    expr,
    @ast.GetAttr(@ast.GetAttr(@ast.Var(@ast.Context), "foo"), "bar"),
  )
}

///|
test "parse bracket access" {
  let expr = parse_expr_src("context[\"2legit2quit\"]")
  @debug.assert_eq(expr, @ast.GetAttr(@ast.Var(@ast.Context), "2legit2quit"))
}

///|
test "parse contains method" {
  let expr = parse_expr_src("context.strings.contains(\"foo\")")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.Contains,
      @ast.GetAttr(@ast.Var(@ast.Context), "strings"),
      @ast.Lit(@ast.String("foo")),
    ),
  )
}

///|
test "parse containsAll method" {
  let expr = parse_expr_src("context.strings.containsAll([\"foo\"])")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.ContainsAll,
      @ast.GetAttr(@ast.Var(@ast.Context), "strings"),
      @ast.Set([@ast.Lit(@ast.String("foo"))]),
    ),
  )
}

///|
test "parse containsAny method" {
  let expr = parse_expr_src("context.strings.containsAny([\"foo\"])")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.ContainsAny,
      @ast.GetAttr(@ast.Var(@ast.Context), "strings"),
      @ast.Set([@ast.Lit(@ast.String("foo"))]),
    ),
  )
}

///|
test "parse isEmpty method" {
  let expr = parse_expr_src("context.strings.isEmpty()")
  @debug.assert_eq(
    expr,
    @ast.UnaryApp(@ast.IsEmpty, @ast.GetAttr(@ast.Var(@ast.Context), "strings")),
  )
}

///|
test "parse hasTag method" {
  let expr = parse_expr_src("principal.hasTag(\"blue\")")
  @debug.assert_eq(
    expr,
    @ast.HasTag(@ast.Var(@ast.Principal), @ast.Lit(@ast.String("blue"))),
  )
}

///|
test "parse getTag method" {
  let expr = parse_expr_src("principal.getTag(\"blue\")")
  @debug.assert_eq(
    expr,
    @ast.GetTag(@ast.Var(@ast.Principal), @ast.Lit(@ast.String("blue"))),
  )
}

///|
test "parse extension method call" {
  let expr = parse_expr_src("context.sourceIP.isIpv4()")
  @debug.assert_eq(
    expr,
    @ast.ExtensionApp({ ns: [], name: "isIpv4" }, [
      @ast.GetAttr(@ast.Var(@ast.Context), "sourceIP"),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Ternary — if then else
// ---------------------------------------------------------------------------

///|
test "parse if then else" {
  let expr = parse_expr_src("if true then true else false")
  @debug.assert_eq(
    expr,
    @ast.If(
      @ast.Lit(@ast.Bool(true)),
      @ast.Lit(@ast.Bool(true)),
      @ast.Lit(@ast.Bool(false)),
    ),
  )
}

///|
test "parse nested if then else" {
  let expr = parse_expr_src("if false then principal else principal")
  @debug.assert_eq(
    expr,
    @ast.If(
      @ast.Lit(@ast.Bool(false)),
      @ast.Var(@ast.Principal),
      @ast.Var(@ast.Principal),
    ),
  )
}

// ---------------------------------------------------------------------------
// Precedence
// ---------------------------------------------------------------------------

///|
test "precedence mult over add" {
  let expr = parse_expr_src("2 * 3 + 4")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.Add,
      @ast.BinaryApp(@ast.Mul, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(3L))),
      @ast.Lit(@ast.Long(4L)),
    ),
  )
}

///|
test "precedence add over rel" {
  let expr = parse_expr_src("1 + 1 < 3")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(
      @ast.Less,
      @ast.BinaryApp(@ast.Add, @ast.Lit(@ast.Long(1L)), @ast.Lit(@ast.Long(1L))),
      @ast.Lit(@ast.Long(3L)),
    ),
  )
}

///|
test "precedence rel over and" {
  let expr = parse_expr_src("1 < 2 && true")
  @debug.assert_eq(
    expr,
    @ast.And(
      @ast.BinaryApp(
        @ast.Less,
        @ast.Lit(@ast.Long(1L)),
        @ast.Lit(@ast.Long(2L)),
      ),
      @ast.Lit(@ast.Bool(true)),
    ),
  )
}

///|
test "precedence and over or" {
  let expr = parse_expr_src("true && false || true && true")
  // && binds tighter than || (Cedar spec precedence: Or < And < Relation < Add < Mult)
  @debug.assert_eq(
    expr,
    @ast.Or(
      @ast.And(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(false))),
      @ast.And(@ast.Lit(@ast.Bool(true)), @ast.Lit(@ast.Bool(true))),
    ),
  )
}

///|
test "parse multiplication with negative literal" {
  let expr = parse_expr_src("-2 * 3")
  @debug.assert_eq(
    expr,
    @ast.BinaryApp(@ast.Mul, @ast.Lit(@ast.Long(-2L)), @ast.Lit(@ast.Long(3L))),
  )
}

///|
test "precedence parens over unary" {
  let expr = parse_expr_src("-(2 + 3)")
  @debug.assert_eq(
    expr,
    @ast.UnaryApp(
      @ast.Neg,
      @ast.BinaryApp(@ast.Add, @ast.Lit(@ast.Long(2L)), @ast.Lit(@ast.Long(3L))),
    ),
  )
}

///|
test "parse parenthesized expression" {
  let expr = parse_expr_src("(true)")
  @debug.assert_eq(expr, @ast.Lit(@ast.Bool(true)))
}

///|
test "parse parenthesized if" {
  let expr = parse_expr_src("(if true then 2 else 3)")
  @debug.assert_eq(
    expr,
    @ast.If(
      @ast.Lit(@ast.Bool(true)),
      @ast.Lit(@ast.Long(2L)),
      @ast.Lit(@ast.Long(3L)),
    ),
  )
}

// ---------------------------------------------------------------------------
// Chained has — principal has a.b.c
// ---------------------------------------------------------------------------

///|
test "parse chained has" {
  let expr = parse_expr_src("principal has a.b.c")
  let pa = @ast.Var(@ast.Principal)
  @debug.assert_eq(
    expr,
    @ast.And(
      @ast.And(@ast.HasAttr(pa, "a"), @ast.HasAttr(@ast.GetAttr(pa, "a"), "b")),
      @ast.HasAttr(@ast.GetAttr(@ast.GetAttr(pa, "a"), "b"), "c"),
    ),
  )
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

///|
test "error invalid unary plus" {
  let mut raised = false
  try parse_expr_src("+resource.bar") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error incomplete add" {
  let mut raised = false
  try parse_expr_src("resource.foo +") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error incomplete in" {
  let mut raised = false
  try parse_expr_src("resource.name in") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error incomplete has" {
  let mut raised = false
  try parse_expr_src("resource.name has") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error incomplete like" {
  let mut raised = false
  try parse_expr_src("resource.name like") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error has with numeric rhs" {
  let mut raised = false
  try parse_expr_src("resource.name has 123") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error like with unquoted pattern" {
  let mut raised = false
  try parse_expr_src("resource.name like foo") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error like with numeric pattern" {
  let mut raised = false
  try parse_expr_src("context.key like 42") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error unmatched open paren" {
  let mut raised = false
  try parse_expr_src("(") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error unmatched close paren on if" {
  let mut raised = false
  try parse_expr_src("(true") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error if missing then" {
  let mut raised = false
  try parse_expr_src("if true") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error if missing else" {
  let mut raised = false
  try parse_expr_src("if true then false") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error access dot missing field" {
  let mut raised = false
  try parse_expr_src("resource.") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error bracket missing string" {
  let mut raised = false
  try parse_expr_src("resource.bar[baz]") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error bracket unterminated" {
  let mut raised = false
  try parse_expr_src("resource.bar[\"baz\"") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error unmatching brackets in access" {
  let mut raised = false
  try parse_expr_src("resource.bar[\"baz\")") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error extension function unterminated" {
  let mut raised = false
  try parse_expr_src("abcd(") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error extension function unterminated args" {
  let mut raised = false
  try parse_expr_src("abcd(123") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error set unterminated" {
  let mut raised = false
  try parse_expr_src("[") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error record unterminated" {
  let mut raised = false
  try parse_expr_src("{") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error numeric record key" {
  let mut raised = false
  try parse_expr_src("{123: \"value\"}") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error record missing colon" {
  let mut raised = false
  try parse_expr_src("{\"key\" \"value\"}") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error record incomplete entry" {
  let mut raised = false
  try parse_expr_src("{\"key\":") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error is with numeric type" {
  let mut raised = false
  try parse_expr_src("principal is 1") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}
