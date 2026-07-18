# MoonCedar

A [Cedar](https://www.cedarpolicy.com) policy engine implemented in MoonBit — parser, evaluator, and authorizer.

## Installation

```bash
moon add jaredzhou/mooncedar@0.1.1
```

## Quick Start

```moonbit
// 1. Parse a Cedar policy
let policies = parse_policies(
  #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");|
)

// 2. Build an entity store from JSON
let entities_src =
  #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]
let store : MapEntityStore = @json.from_json(@json.parse(entities_src))

// 3. Create a request
let req = Request::{
  principal: @evaluator.concrete_uid("User", "alice"),
  action: @evaluator.concrete_uid("Action", "view"),
  resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
  context: Context::Concrete(Value::Record(Map([]))),
}

// 4. Authorize
let result = is_authorized(req, policies.iter(), store)
match result.decision {
  Decision::Allow => println("permitted")
  Decision::Deny => println("denied")
}
// => permitted
```

For a complete, runnable example (multi-user todo app with Cedar policies, pony HTTP routing, and a CLI client), see [moon-examples/todo](https://github.com/jaredzhou/moon-examples/tree/main/todo).

## Packages

| Package | Purpose |
|---------|---------|
| `jaredzhou/mooncedar` | Unified API: `parse_policies`, `stringify`, builder fns, type aliases (`Expr`, `Policy`, `Request`, `Value`, ...), `MapEntityStore`, `is_authorized`, `evaluate`, `reauthorize` |
| `jaredzhou/mooncedar/ast` | Core AST: `Expr`, `Policy`, `Entity`, `EntityUID`, `Value`, `PartialValue`, `Type` + builder methods |
| `jaredzhou/mooncedar/evaluator` | `EntityStore` trait, `EvalError`, `Request`, `Context`, `EntityUIDEntry`, helpers (`concrete_uid`, `unknown_uid`) |
| `jaredzhou/mooncedar/parser` | Lexer, recursive descent parser, `stringify` |

Root `types.mbt` re-exports all commonly-used types as `pub type` aliases and builder functions, so most users only need `import { "jaredzhou/mooncedar" }`.

## Features

### Policy Language

Full Cedar policy syntax support:

- `permit` / `forbid` effects with annotations
- Scope constraints (`==`, `in`, `in [set]`, `All`)
- `when` / `unless` conditions
- Expression language: `&&`, `||`, `!`, `>`, `<`, `>=`, `<=`, `!=`, `like`, `in`, `contains`, `has`, `.`, `.tag`
- Records, sets, if-then-else, extension function calls

### Expression Builder

```moonbit
let e = expr_principal()
  .eq(expr_str("alice"))
  .and_(expr_resource()
    .has_tag(expr_str("confidential"))
  )
```

### Policy Builder

```moonbit
let policy = default_policy()
  .permit()
  .principal_eq("User", "alice")
  .action_eq("Action", "view")
  .resource_in("Album", "photos")
  .when_(expr_resource().has_tag(expr_str("public")))
```

### Strategy Validation

```moonbit
let errors = @ast.validate_policies(policies)
```

### Entity Store (Pluggable)

```moonbit
// In-memory store (built-in)
let store = new_map_store()

// From Cedar JSON
let store : MapEntityStore = @json.from_json(@json.parse(entities_src))

// Custom backend via pub(open) trait
struct DbStore { conn : Connection }
pub impl @evaluator.EntityStore for DbStore with get_entity(self, uid) {
  db_lookup(self.conn, uid)
}
```

Entity hierarchy: `is_descendant` uses BFS for ancestor traversal. Wildcard matching uses two-pointer backtracking.

### Partial Evaluation

Support for 4 sources of unknown during partial eval — policies evaluate to residual expressions that can be re-evaluated when more information is available:

```moonbit
let answer = evaluate(req, policies.iter(), store1)        // partial result
let answer = answer.reauthorize(req, store2, mapping)      // fill unknowns
let result = answer.concretize()                           // final decision
```

The `reauthorize` method accepts an expanded entity store and a `Map[String, Value]` mapping to resolve unknowns by name.

### Request JSON

```moonbit
// Strings: "Type::\"id\"" → Concrete, "Type" → Unknown
// Objects: {"type":"...","id":"..."} → Concrete
let src =
  #|{"principal":"User::\"alice\"","action":"Action::\"view\"","resource":"Photo::\"x\"","context":{}}|
let dto : RequestJSON = @json.from_json(@json.parse(src))
let req : Request = dto.to_request()
let json = to_request_json(req).to_json()
```

### Stringify (AST -> Cedar Source)

```moonbit
let src = stringify(policies)
```

## Status

- **572 tests** passing (parser, evaluator, authorizer, JSON, reauthorize, RequestJSON)
- Entity stores as pluggable `pub(open)` traits
- JSON serialization (Cedar-compatible format) for entities and requests
- Policy validation
- Full expression evaluation (18 expression variants, 12 binary + 3 unary operators)
- Partial evaluation with reauthorize (4-category coverage)

## License

Apache-2.0
