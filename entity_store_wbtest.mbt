// MapEntityStore JSON (ToJson / FromJson) — blackbox tests via inspect snapshot.

///|
test "to_json empty store" {
  let store : MapEntityStore = @json.from_json(@json.parse("[]"))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[]
    ),
  )
}

///|
test "to_json single entity" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":"admin"},"tags":{},"parents":[]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]}]
    ),
  )
}

///|
test "to_json entity with parents and tags" {
  let src =
    #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{"env":"prod"},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{"env":["String","prod"]},"parents":[{"type":"Album","id":"vacation"}]}]
    ),
  )
}

///|
test "to_json multiple entities" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
    ),
  )
}

///|
test "from_json recovers entities" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":"admin"},"tags":{},"parents":[]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  match store.get_entity(EntityUID::{ type_: "User", id: "alice" }) {
    Some(e) => {
      @debug.assert_eq("User", e.uid.type_)
      @debug.assert_eq("alice", e.uid.id)
    }
    None => @debug.assert_eq("should find alice", "missing")
  }
}

///|
test "from_json entity hierarchy preserved" {
  let src =
    #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  match store.get_entity(EntityUID::{ type_: "Photo", id: "x.jpg" }) {
    Some(e) => {
      @debug.assert_eq(1, e.parents.length())
      @debug.assert_eq("Album", e.parents[0].type_)
      @debug.assert_eq("vacation", e.parents[0].id)
    }
    None => @debug.assert_eq("should find photo", "missing")
  }
}

///|
test "from_json wrong shape raises error" {
  let src =
    #|{"not":"an array"}
  let json = @json.parse(src)
  let mut raised = false
  try {
    let _store : MapEntityStore = @json.from_json(json)
  } catch {
    _ => raised = true
  }
  @debug.assert_eq(true, raised)
}

// ---------------------------------------------------------------------------
// RequestJSON roundtrip tests
// ---------------------------------------------------------------------------

///|
test "request json roundtrip: concrete PARC" {
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("GitApp::User", "JaneDoe"),
    action: @evaluator.concrete_uid("GitApp::Action", "addRepoAdmin"),
    resource: @evaluator.concrete_uid("GitApp::Repo", "CodeRepo1"),
    context: @evaluator.Context::Unknown,
  }
  let json = to_request_json(req).to_json()
  let parsed : RequestJSON = @json.from_json(json)
  let req2 = parsed.to_request()
  @debug.assert_eq(req, req2)
}

///|
test "request json: unknown principal" {
  let req = @evaluator.Request::{
    principal: @evaluator.unknown_uid("User"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Unknown,
  }
  let json = to_request_json(req).to_json()
  let parsed : RequestJSON = @json.from_json(json)
  guard parsed.principal is Some(s) else { return }
  @debug.assert_eq(s, "User")
}

///|
test "request json: entity object format → roundtrip" {
  let src =
    #|{"principal":{"type":"User","id":"alice"},"action":{"type":"Action","id":"view"},"resource":{"type":"Photo","id":"x"},"context":{}}
  let json = @json.parse(src)
  let dto : RequestJSON = @json.from_json(json)
  // object format was normalised to string "Type::\"id\""
  guard dto.principal is Some(p) else { return }
  let expected = p
  @debug.assert_eq("User::\"alice\"", expected)
  guard dto.action is Some(a) else { return }
  @debug.assert_eq("Action::\"view\"", a)
  guard dto.resource is Some(r) else { return }
  @debug.assert_eq("Photo::\"x\"", r)
}
