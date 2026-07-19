// Policy parser tests — whitebox tests covering single-policy parsing.
// Uses @ast builder for expected policy construction.
// References: cedar-go/internal/parser/cedar_parse_test.go
//             cedar-go/internal/parser/cedar_unmarshal_test.go

// ---------------------------------------------------------------------------
// Helper — parse a single policy from source text
// ---------------------------------------------------------------------------

///|
fn parse_one_policy(src : String) -> @ast.Policy raise ParseError {
  let policies = parse_policies(src)
  policies[0]
}

// ---------------------------------------------------------------------------
// Basic policies
// ---------------------------------------------------------------------------

///|
test "parse permit any scope" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource);"),
    @ast.default().with_id("policy").permit(),
  )
}

///|
test "parse forbid any scope" {
  @debug.assert_eq(
    parse_one_policy("forbid(principal, action, resource);"),
    @ast.default().with_id("policy").forbid(),
  )
}

// ---------------------------------------------------------------------------
// Scope constraints — Eq
// ---------------------------------------------------------------------------

///|
test "parse scope principal eq" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal == User::"alice",
        #|  action == PhotoOp::"view",
        #|  resource == Photo::"VacationPhoto94.jpg"
        #|);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .principal_eq("User", "alice")
    .action_eq("PhotoOp", "view")
    .resource_eq("Photo", "VacationPhoto94.jpg"),
  )
}

// ---------------------------------------------------------------------------
// Scope constraints — In
// ---------------------------------------------------------------------------

///|
test "parse scope principal in" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal in Team::"admins",
        #|  action,
        #|  resource
        #|);
      ),
    ),
    @ast.default().with_id("policy").permit().principal_in("Team", "admins"),
  )
}

///|
test "parse scope action in single entity" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal,
        #|  action in PhotoflashRole::"admin",
        #|  resource in Album::"jane_vacation"
        #|);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .action_in("PhotoflashRole", "admin")
    .resource_in("Album", "jane_vacation"),
  )
}

// ---------------------------------------------------------------------------
// Scope constraints — InSet (action in [...])
// ---------------------------------------------------------------------------

///|
test "parse scope action in set" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal,
        #|  action in [PhotoOp::"view", PhotoOp::"delete"],
        #|  resource
        #|);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .action_in_set([("PhotoOp", "view"), ("PhotoOp", "delete")]),
  )
}

///|
test "parse scope action in set single" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal,
        #|  action in [PhotoOp::"view"],
        #|  resource
        #|);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .action_in_set([("PhotoOp", "view")]),
  )
}

///|
test "parse scope action in set with namespaced entities" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(
        #|  principal,
        #|  action in [Action::Group::"read", Action::Group::"write"],
        #|  resource
        #|);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .action_in_set([("Action::Group", "read"), ("Action::Group", "write")]),
  )
}

///|
test "parse scope action in set with trailing skip" {
  let p = parse_one_policy(
    (
      #|permit(
      #|  principal,
      #|  action in [PhotoOp::"view", PhotoOp::"delete",],
      #|  resource
      #|);
    ),
  )
  @debug.assert_eq(p.effect, @ast.Permit)
  @debug.assert_eq(
    p.action,
    @ast.InSet([
      @ast.EntityUID::{ type_: "PhotoOp", id: "view" },
      @ast.EntityUID::{ type_: "PhotoOp", id: "delete" },
    ]),
  )
}

// ---------------------------------------------------------------------------
// Scope constraints — Is, IsIn
// ---------------------------------------------------------------------------

///|
test "parse scope principal is" {
  @debug.assert_eq(
    parse_one_policy("permit(principal is User, action, resource);"),
    @ast.default().with_id("policy").permit().principal_is("User"),
  )
}

///|
test "parse scope principal is long" {
  @debug.assert_eq(
    parse_one_policy("permit(principal is X::Y, action, resource);"),
    @ast.default().with_id("policy").permit().principal_is("X::Y"),
  )
}

///|
test "parse scope principal is in" {
  @debug.assert_eq(
    parse_one_policy("permit(principal is X in X::\"z\", action, resource);"),
    @ast.default().with_id("policy").permit().principal_is_in("X", "X", "z"),
  )
}

///|
test "parse scope resource is" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource is X);"),
    @ast.default().with_id("policy").permit().resource_is("X"),
  )
}

///|
test "parse scope resource is long" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource is X::Y);"),
    @ast.default().with_id("policy").permit().resource_is("X::Y"),
  )
}

///|
test "parse scope resource is in" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource is X in X::\"z\");"),
    @ast.default().with_id("policy").permit().resource_is_in("X", "X", "z"),
  )
}

///|
test "parse scope all scope" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource);"),
    @ast.default().with_id("policy").permit(),
  )
}

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

///|
test "parse when condition int" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { 1234 };"),
    @ast.default().with_id("policy").permit().when_(@ast.long(1234L)),
  )
}

///|
test "parse when condition string" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { \"test string\" };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.str("test string")),
  )
}

///|
test "parse when condition bool" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { true };"),
    @ast.default().with_id("policy").permit().when_(@ast.bool(true)),
  )
}

///|
test "parse unless condition" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) unless { false };"),
    @ast.default().with_id("policy").permit().unless(@ast.bool(false)),
  )
}

///|
test "parse when and unless" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(principal, action, resource)
        #|when { true }
        #|unless { false };
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.bool(true))
    .unless(@ast.bool(false)),
  )
}

///|
test "parse when condition not" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { !true };"),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.not_(@ast.bool(true))),
  )
}

///|
test "parse when condition negate" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { -1 };"),
    @ast.default().with_id("policy").permit().when_(@ast.long(-1L)),
  )
}

///|
test "parse when condition chained not negate" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { !--1 };"),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.not_(@ast.neg(@ast.long(-1L)))),
  )
}

///|
test "parse when condition entity" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { Org::User::\"alice\" };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.euid("Org::User", "alice")),
  )
}

///|
test "parse when condition extension fun" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { ip() };"),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.ext_call(@ast.Name::{ ns: [], name: "ip" }, [])),
  )
}

///|
test "parse when condition if then else" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(principal, action, resource)
        #|when { if false then principal else principal };
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(
      @ast.if_(
        @ast.bool(false),
        @ast.principal(),
        @ast.principal(),
      ),
    ),
  )
}

///|
test "parse when condition access and has with and" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(principal, action, resource)
        #|when { resource.foo has bar && resource.isIpv4() };
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(
      @ast.resource()
      .access("foo")
      .has("bar")
      .and_(
        @ast.ext_call(@ast.Name::{ ns: [], name: "isIpv4" }, [
          @ast.resource(),
        ]),
      ),
    ),
  )
}

///|
test "parse when condition set" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource) when { [true] };"),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.set([@ast.bool(true)])),
  )
}

///|
test "parse when condition record" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { {\"key\": \"some value\"} };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.record([("key", @ast.str("some value"))])),
  )
}

///|
test "parse when condition is" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { principal is X };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.principal().is_(@ast.entity_type("X"))),
  )
}

///|
test "parse when condition is long" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { principal is X::Y };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(@ast.principal().is_(@ast.entity_type("X::Y"))),
  )
}

///|
test "parse when condition is in" {
  @debug.assert_eq(
    parse_one_policy(
      "permit(principal, action, resource) when { principal is X in X::\"z\" };",
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(
      @ast.principal().is_in(
        @ast.entity_type("X"),
        @ast.euid("X", "z"),
      ),
    ),
  )
}

///|
test "parse when condition hasTag getTag" {
  // && binds tighter than == in Cedar spec
  @debug.assert_eq(
    parse_one_policy(
      (
        #|permit(principal, action, resource)
        #|when {
        #|  principal.hasTag("blue") && principal.getTag("blue") == "green"
        #|};
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .when_(
      @ast.principal()
      .has_tag(@ast.str("blue"))
      .and_(
        @ast.principal()
        .get_tag(@ast.str("blue"))
        .eq(@ast.str("green")),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

///|
test "parse one annotation" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@foo("bar")
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default().with_id("policy").permit().annotate("foo", "bar"),
  )
}

///|
test "parse two annotations" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@foo("bar")
        #|@baz("quux")
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .annotate("foo", "bar")
    .annotate("baz", "quux"),
  )
}

///|
test "parse bare annotation" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@foo
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default().with_id("policy").permit().annotate("foo", ""),
  )
}

///|
test "parse bare and valued annotations" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@bare
        #|@valued("v")
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default()
    .with_id("policy")
    .permit()
    .annotate("bare", "")
    .annotate("valued", "v"),
  )
}

///|
test "parse annotation reserved keyword key" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@is("bar")
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default().with_id("policy").permit().annotate("is", "bar"),
  )
}

///|
test "parse bare annotation reserved keyword key" {
  @debug.assert_eq(
    parse_one_policy(
      (
        #|@is
        #|permit(principal, action, resource);
      ),
    ),
    @ast.default().with_id("policy").permit().annotate("is", ""),
  )
}

// ---------------------------------------------------------------------------
// Trailing commas
// ---------------------------------------------------------------------------

///|
test "parse trailing comma after resource" {
  @debug.assert_eq(
    parse_one_policy("permit(principal, action, resource,);"),
    @ast.default().with_id("policy").permit(),
  )
}

// ---------------------------------------------------------------------------
// Multiple policies — parse_policies
// ---------------------------------------------------------------------------

///|
/// Parse multiple policies from source text.
fn policies(src : String) -> Array[@ast.Policy] raise ParseError {
  parse_policies(src)
}

///|
test "parse multiple: two bare policies" {
  let ps = policies(
    (
      #|permit(principal, action, resource);
      #|forbid(principal, action, resource);
    ),
  )
  @debug.assert_eq(ps.length(), 2)
  @debug.assert_eq(ps[0], @ast.default().with_id("policy").permit())
  @debug.assert_eq(ps[1], @ast.default().with_id("policy1").forbid())
}

///|
test "parse multiple: permit and forbid with scopes" {
  let ps = policies(
    (
      #|permit(
      #|  principal == User::"alice",
      #|  action,
      #|  resource
      #|);
      #|forbid(
      #|  principal,
      #|  action == PhotoOp::"delete",
      #|  resource == Photo::"secret.png"
      #|);
    ),
  )
  @debug.assert_eq(ps.length(), 2)
  @debug.assert_eq(
    ps[0],
    @ast.default().with_id("policy").permit().principal_eq("User", "alice"),
  )
  @debug.assert_eq(
    ps[1],
    @ast.default()
    .with_id("policy1")
    .forbid()
    .action_eq("PhotoOp", "delete")
    .resource_eq("Photo", "secret.png"),
  )
}

///|
test "parse multiple: three with conditions" {
  let ps = policies(
    (
      #|permit(principal, action, resource)
      #|when { true };
      #|permit(principal, action, resource)
      #|unless { false };
      #|forbid(principal, action, resource)
      #|when { resource.isIpv4() };
    ),
  )
  @debug.assert_eq(ps.length(), 3)
  @debug.assert_eq(
    ps[0],
    @ast.default().with_id("policy").permit().when_(@ast.bool(true)),
  )
  @debug.assert_eq(
    ps[1],
    @ast.default().with_id("policy1").permit().unless(@ast.bool(false)),
  )
  @debug.assert_eq(
    ps[2],
    @ast.default()
    .with_id("policy2")
    .forbid()
    .when_(
      @ast.ext_call(@ast.Name::{ ns: [], name: "isIpv4" }, [
        @ast.resource(),
      ]),
    ),
  )
}

///|
test "parse multiple: with annotations" {
  let ps = policies(
    (
      #|@id("allow-alice")
      #|permit(
      #|  principal == User::"alice",
      #|  action,
      #|  resource
      #|);
      #|@id("block-bob")
      #|@source("admin")
      #|forbid(
      #|  principal == User::"bob",
      #|  action,
      #|  resource
      #|);
    ),
  )
  @debug.assert_eq(ps.length(), 2)
  @debug.assert_eq(
    ps[0],
    @ast.default().with_id("allow-alice").permit().principal_eq("User", "alice"),
  )
  @debug.assert_eq(
    ps[1],
    @ast.default()
    .with_id("block-bob")
    .forbid()
    .principal_eq("User", "bob")
    .annotate("source", "admin"),
  )
}

///|
test "parse multiple: is and isIn scopes" {
  let ps = policies(
    (
      #|permit(
      #|  principal is User,
      #|  action,
      #|  resource
      #|);
      #|permit(
      #|  principal,
      #|  action,
      #|  resource is Photo
      #|);
      #|permit(
      #|  principal is User in Org::"corp",
      #|  action,
      #|  resource
      #|);
    ),
  )
  @debug.assert_eq(ps.length(), 3)
  @debug.assert_eq(
    ps[0],
    @ast.default().with_id("policy").permit().principal_is("User"),
  )
  @debug.assert_eq(
    ps[1],
    @ast.default().with_id("policy1").permit().resource_is("Photo"),
  )
  @debug.assert_eq(
    ps[2],
    @ast.default()
    .with_id("policy2")
    .permit()
    .principal_is_in("User", "Org", "corp"),
  )
}

///|
test "parse multiple: mixed effects and conditions" {
  let ps = policies(
    (
      #|@id("rule-1")
      #|permit(
      #|  principal in Team::"admins",
      #|  action,
      #|  resource
      #|)
      #|when { resource has public };
      #|@id("rule-2")
      #|forbid(
      #|  principal,
      #|  action in PhotoOp::"delete",
      #|  resource in Album::"private"
      #|);
    ),
  )
  @debug.assert_eq(ps.length(), 2)
  @debug.assert_eq(
    ps[0],
    @ast.default()
    .with_id("rule-1")
    .permit()
    .principal_in("Team", "admins")
    .when_(@ast.resource().has("public")),
  )
  @debug.assert_eq(
    ps[1],
    @ast.default()
    .with_id("rule-2")
    .forbid()
    .action_in("PhotoOp", "delete")
    .resource_in("Album", "private"),
  )
}

///|
test "parse empty string" {
  let ps = policies("")
  @debug.assert_eq(ps.length(), 0)
}

///|
test "parse whitespace only" {
  let ps = policies("  \n  \n  ")
  @debug.assert_eq(ps.length(), 0)
}

///|
test "parse multiple: single policy via parse_policies" {
  let ps = policies("permit(principal, action, resource);")
  @debug.assert_eq(ps.length(), 1)
  @debug.assert_eq(ps[0], @ast.default().with_id("policy").permit())
}

// ---------------------------------------------------------------------------
// Error cases — malformed policies
// ---------------------------------------------------------------------------

///|

///|
test "error missing effect" {
  let mut raised = false
  try parse_one_policy("@id(\"test\")") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid effect" {
  let mut raised = false
  try
    parse_one_policy("invalidEffect(principal, action, resource);") |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error missing semicolon" {
  let mut raised = false
  try parse_one_policy("permit(principal, action, resource)") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error missing scope" {
  let mut raised = false
  try parse_one_policy("permit;") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error eof in scope" {
  let mut raised = false
  try parse_one_policy("permit(principal") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error missing scope end paren" {
  let mut raised = false
  try parse_one_policy("permit(principal, action, resource;") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error missing entity" {
  let mut raised = false
  try parse_one_policy("permit(principal ==") |> ignore catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid entity bare string" {
  let mut raised = false
  try
    parse_one_policy("permit(principal == \"alice\", action, resource);")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid entity missing id" {
  let mut raised = false
  try
    parse_one_policy("permit(principal == User::, action, resource);") |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid annotation string key" {
  let mut raised = false
  try
    parse_one_policy("@\"annotate\"\npermit(principal, action, resource);")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid annotation unterminated" {
  let mut raised = false
  try
    parse_one_policy("@annotate(\npermit(principal, action, resource);")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid annotation bracket" {
  let mut raised = false
  try
    parse_one_policy("@annotate[\"\"]\npermit(principal, action, resource);")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error invalid annotation unquoted value" {
  let mut raised = false
  try
    parse_one_policy("@annotate(test)\npermit(principal, action, resource);")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error empty when condition" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when") |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error empty condition body" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when {}") |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error unterminated condition" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when { true")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error condition missing closing brace" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when {") |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error if missing then in policy" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when { if }")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error if missing else in policy" {
  let mut raised = false
  try
    parse_one_policy(
      "permit(principal, action, resource) when { if true then }",
    )
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error access dot missing field in policy" {
  let mut raised = false
  try
    parse_one_policy("permit(principal, action, resource) when { resource. }")
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error access bracket missing string in policy" {
  let mut raised = false
  try
    parse_one_policy(
      "permit(principal, action, resource) when { resource.bar[baz] }",
    )
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}

///|
test "error mismatched brackets in condition" {
  let mut raised = false
  try
    parse_one_policy(
      "permit(principal, action, resource) when { resource.bar(] }",
    )
    |> ignore
  catch {
    ParseError(_, _) => raised = true
  }
  assert_eq(raised, true)
}
