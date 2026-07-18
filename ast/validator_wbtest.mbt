// Policy validator tests — whitebox tests for scope constraint validation.
// References: cedar-policy/cedar — validator tests

// ---------------------------------------------------------------------------
// Positive — valid scope combinations
// ---------------------------------------------------------------------------

///|
test "validate: all All scopes" {
  let p = default()
  validate_policy(p) |> ignore
}

///|
test "validate: principal Eq" {
  let p = default().principal_eq("User", "alice")
  validate_policy(p) |> ignore
}

///|
test "validate: principal In" {
  let p = default().principal_in("Team", "admins")
  validate_policy(p) |> ignore
}

///|
test "validate: principal Is" {
  let p = default().principal_is("User")
  validate_policy(p) |> ignore
}

///|
test "validate: principal IsIn" {
  let p = default().principal_is_in("User", "Org", "corp")
  validate_policy(p) |> ignore
}

///|
test "validate: action Eq" {
  let p = default().action_eq("PhotoOp", "view")
  validate_policy(p) |> ignore
}

///|
test "validate: action In" {
  let p = default().action_in("PhotoOp", "view")
  validate_policy(p) |> ignore
}

///|
test "validate: action InSet" {
  let p = default().action_in_set([("PhotoOp", "view"), ("PhotoOp", "delete")])
  validate_policy(p) |> ignore
}

///|
test "validate: resource Eq" {
  let p = default().resource_eq("Photo", "sunset.jpg")
  validate_policy(p) |> ignore
}

///|
test "validate: resource In" {
  let p = default().resource_in("Album", "vacation")
  validate_policy(p) |> ignore
}

///|
test "validate: resource Is" {
  let p = default().resource_is("Photo")
  validate_policy(p) |> ignore
}

///|
test "validate: resource IsIn" {
  let p = default().resource_is_in("Photo", "Album", "vacation")
  validate_policy(p) |> ignore
}

///|
test "validate: full valid policy" {
  let p = default()
    .permit()
    .principal_eq("User", "alice")
    .action_in_set([("PhotoOp", "view")])
    .resource_is("Photo")
  validate_policy(p) |> ignore
}

// ---------------------------------------------------------------------------
// Negative — principal InSet
// ---------------------------------------------------------------------------

///|
test "validate: principal InSet raises" {
  let p = Policy::{
    ..default(),
    principal: InSet([EntityUID::{ type_: "User", id: "alice" }]),
  }
  let mut raised = false
  try validate_policy(p) |> ignore catch {
    ValidationError(msg, _) => {
      assert_eq(msg.contains("principal"), true)
      assert_eq(msg.contains("InSet"), true)
      raised = true
    }
  }
  assert_eq(raised, true)
}

// ---------------------------------------------------------------------------
// Negative — action Is
// ---------------------------------------------------------------------------

///|
test "validate: action Is raises" {
  let p = Policy::{ ..default(), action: Is(EntityType("PhotoOp")) }
  let mut raised = false
  try validate_policy(p) |> ignore catch {
    ValidationError(msg, _) => {
      assert_eq(msg.contains("action"), true)
      assert_eq(msg.contains("is"), true)
      raised = true
    }
  }
  assert_eq(raised, true)
}

///|
test "validate: action IsIn raises" {
  let p = Policy::{
    ..default(),
    action: IsIn(EntityType("PhotoOp"), EntityUID::{ type_: "Meta", id: "ops" }),
  }
  let mut raised = false
  try validate_policy(p) |> ignore catch {
    ValidationError(msg, _) => {
      assert_eq(msg.contains("action"), true)
      raised = true
    }
  }
  assert_eq(raised, true)
}

// ---------------------------------------------------------------------------
// Negative — resource InSet
// ---------------------------------------------------------------------------

///|
test "validate: resource InSet raises" {
  let p = Policy::{
    ..default(),
    resource: InSet([EntityUID::{ type_: "Photo", id: "a.jpg" }]),
  }
  let mut raised = false
  try validate_policy(p) |> ignore catch {
    ValidationError(msg, _) => {
      assert_eq(msg.contains("resource"), true)
      assert_eq(msg.contains("InSet"), true)
      raised = true
    }
  }
  assert_eq(raised, true)
}

// ---------------------------------------------------------------------------
// validate_policies — batch validation
// ---------------------------------------------------------------------------

///|
test "validate_policies: all valid passes" {
  let ps = [default().permit(), default().forbid()]
  validate_policies(ps) |> ignore
}

///|
test "validate_policies: stops on first error" {
  let ps = [
    default().permit(),
    Policy::{ ..default(), action: Is(EntityType("Bad")) }, // index 1 — invalid
    default().principal_eq("User", "bob"), // index 2 — valid but shouldn't be reached
  ]
  let mut raised = false
  try validate_policies(ps) |> ignore catch {
    ValidationError(_, _) => raised = true
  }
  assert_eq(raised, true)
}
