// Cedar parser -- policy-level recursive descent with ArrayView threading.

///|
/// Parse one or more Cedar policies from source text.
/// Each policy is validated immediately after parsing.
pub fn parse_policies(src : String) -> Array[@ast.Policy] raise ParseError {
  let tokens = tokenize(src)
  let policies : Array[@ast.Policy] = []
  let mut auto_id = 0
  let _ = for rest = tokens[:] {
    match rest {
      [{ kind: EOF, .. }] => break rest
      _ => {
        let (raw, rest) = parse_policy(rest)
        let mut policy = raw
        if policy.id == "" {
          let n = if auto_id == 0 { "" } else { auto_id.to_string() }
          policy = { ..policy, id: "policy\{n}" }
          auto_id = auto_id + 1
        }
        policies.push(policy)
        continue rest
      }
    }
  }
  policies
}

///|
/// Parse a single policy: @annotations effect(principal, action, resource) conditions;
fn parse_policy(
  tokens : ArrayView[Token],
) -> (@ast.Policy, ArrayView[Token]) raise ParseError {
  // annotations: @key(value) @key ...
  let (anns, rest) = parse_annotations(tokens)

  // Extract @id annotation as the policy id, remove from annotations
  let (id, anns) = extract_id(anns)

  // effect: permit | forbid
  let (effect, rest) = parse_effect(rest)

  // scope: ( principal, action, resource )
  guard rest is [{ kind: Bracket('('), .. }, .. rest] else {
    raise ParseError("expected '(' after effect", rest[0].pos)
  }

  let (principal, rest) = parse_scope_principal(rest)
  guard rest is [{ kind: Symbol(","), .. }, .. rest] else {
    raise ParseError("expected ','", rest[0].pos)
  }

  let (action, rest) = parse_scope_action(rest)
  guard rest is [{ kind: Symbol(","), .. }, .. rest] else {
    raise ParseError("expected ','", rest[0].pos)
  }

  let (resource, rest) = parse_scope_resource(rest)
  // optional trailing comma
  let rest = if rest is [{ kind: Symbol(","), .. }, .. rest] {
    rest
  } else {
    rest
  }
  guard rest is [{ kind: Bracket(')'), .. }, .. rest] else {
    raise ParseError("expected ')'", rest[0].pos)
  }

  // conditions
  let (conds, rest) = parse_conditions(rest)

  // terminator
  guard rest is [{ kind: Symbol(";"), .. }, .. rest] else {
    raise ParseError("expected ';'", rest[0].pos)
  }

  let policy : @ast.Policy = {
    id,
    effect,
    annotations: anns,
    principal,
    action,
    resource,
    conditions: conds,
  }

  // Semantic validation: check scope constraint validity per PARC position
  @ast.validate_policy(policy) catch {
    @ast.ValidationError(msg, _) =>
      raise ParseError(msg, @ast.Position::{
        filename: "",
        offset: 0,
        line: 0,
        column: 0,
      })
  }

  (policy, rest)
}

// ---------------------------------------------------------------------------
// Annotations: @key(value) @key ...
// ---------------------------------------------------------------------------

///|
fn parse_annotations(
  tokens : ArrayView[Token],
) -> (Array[@ast.Annotation], ArrayView[Token]) raise ParseError {
  let annotations : Array[@ast.Annotation] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Symbol("@"), .. }, .. rest] => {
        let (ann, rest) = parse_annotation(rest)
        annotations.push(ann)
        continue rest
      }
      _ => break rest
    }
  }
  (annotations, rest)
}

///|
fn parse_annotation(
  tokens : ArrayView[Token],
) -> (@ast.Annotation, ArrayView[Token]) raise ParseError {
  guard tokens is [head, .. rest] else {
    raise ParseError("expected annotation key", tokens[0].pos)
  }
  let key = match head.kind {
    Ident(k) => k
    Keyword(k) => keyword_string(k)
    _ => raise ParseError("expected annotation key", head.pos)
  }

  match rest {
    [{ kind: Bracket('('), .. }, .. rest] => {
      guard rest is [{ kind: String(v), .. }, .. r3] else {
        raise ParseError("expected annotation string value", rest[0].pos)
      }
      guard r3 is [{ kind: Bracket(')'), .. }, .. r4] else {
        raise ParseError("expected ')' in annotation", r3[0].pos)
      }
      ({ key, value: v }, r4)
    }
    _ => ({ key, value: "" }, rest)
  }
}

///|
/// Extract @id annotation value as the policy id, removing it from annotations.
/// Returns ("", anns) if no @id annotation is present.
fn extract_id(
  anns : Array[@ast.Annotation],
) -> (String, Array[@ast.Annotation]) {
  let mut matched_id = ""
  let filtered = []
  for ann in anns {
    if ann.key == "id" && matched_id == "" {
      matched_id = ann.value
    } else {
      filtered.push(ann)
    }
  }
  (matched_id, filtered)
}

// ---------------------------------------------------------------------------
// Effect: permit | forbid
// ---------------------------------------------------------------------------

///|
fn parse_effect(
  tokens : ArrayView[Token],
) -> (@ast.PolicyEffect, ArrayView[Token]) raise ParseError {
  guard tokens is [head, .. rest] else {
    raise ParseError("expected 'permit' or 'forbid'", tokens[0].pos)
  }
  match head.kind {
    Keyword(Permit) => (@ast.Permit, rest)
    Keyword(Forbid) => (@ast.Forbid, rest)
    _ => raise ParseError("expected 'permit' or 'forbid'", head.pos)
  }
}

// ---------------------------------------------------------------------------
// Scope: principal, action, resource
// ---------------------------------------------------------------------------

///|
fn parse_scope_principal(
  tokens : ArrayView[Token],
) -> (@ast.ScopeConstraint, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident("principal"), .. }, .. rest] else {
    raise ParseError("expected 'principal'", tokens[0].pos)
  }
  parse_scope_op(rest)
}

///|
fn parse_scope_action(
  tokens : ArrayView[Token],
) -> (@ast.ScopeConstraint, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident("action"), .. }, .. rest] else {
    raise ParseError("expected 'action'", tokens[0].pos)
  }
  parse_scope_op(rest)
}

///|
fn parse_scope_resource(
  tokens : ArrayView[Token],
) -> (@ast.ScopeConstraint, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident("resource"), .. }, .. rest] else {
    raise ParseError("expected 'resource'", tokens[0].pos)
  }
  parse_scope_op(rest)
}

///|
fn parse_scope_op(
  tokens : ArrayView[Token],
) -> (@ast.ScopeConstraint, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Op(Eq), .. }, .. rest] => {
      let (entity, rest) = parse_entity_uid(rest)
      (@ast.Eq(entity), rest)
    }
    [{ kind: Keyword(In), .. }, .. rest] =>
      // InSet: action in [EntityUID, EntityUID, ...]
      if rest.length() > 0 && rest[0].kind == Bracket('[') {
        let (entities, rest) = parse_entity_uid_list(rest[1:])
        (@ast.InSet(entities), rest)
      } else {
        let (entity, rest) = parse_entity_uid(rest)
        (@ast.In(entity), rest)
      }
    [{ kind: Keyword(Is), .. }, .. rest] => {
      let (etype, rest) = parse_entity_type(rest)
      match rest {
        [{ kind: Keyword(In), .. }, .. rest] => {
          let (entity, rest) = parse_entity_uid(rest)
          (@ast.IsIn(etype, entity), rest)
        }
        _ => (@ast.Is(etype), rest)
      }
    }
    _ => (@ast.All, tokens)
  }
}

// ---------------------------------------------------------------------------
// Entity UIDs and types
// ---------------------------------------------------------------------------

///|
fn parse_entity_uid(
  tokens : ArrayView[Token],
) -> (@ast.EntityUID, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident(first), .. }, .. rest] else {
    raise ParseError("expected entity type (uppercase)", tokens[0].pos)
  }
  let mut etype = first
  for rest = rest {
    match rest {
      [{ kind: Symbol("::"), .. }, .. rest] =>
        match rest {
          [{ kind: Ident(next), .. }, .. r3] => {
            etype = "\{etype}::\{next}"
            continue r3
          }
          [{ kind: String(id), .. }, .. r3] => return ({ type_: etype, id }, r3)
          [t, ..] => raise ParseError("expected type or id after ::", t.pos)
          [] => raise ParseError("expected type or id after ::", tokens[0].pos)
        }
      _ =>
        raise ParseError("expected '::' in entity UID", @ast.Position::{
          filename: "",
          offset: 0,
          line: 0,
          column: 0,
        })
    }
  }
  raise ParseError("expected '::' in entity UID", @ast.Position::{
    filename: "",
    offset: 0,
    line: 0,
    column: 0,
  })
}

///|
/// Parse a comma-separated list of entity UIDs: EntityUID, EntityUID, ... ]
/// The '[' is already consumed by the caller.
fn parse_entity_uid_list(
  tokens : ArrayView[Token],
) -> (Array[@ast.EntityUID], ArrayView[Token]) raise ParseError {
  let entities : Array[@ast.EntityUID] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Bracket(']'), .. }, .. r1] => break r1
      _ => {
        let (entity, r2) = parse_entity_uid(rest)
        entities.push(entity)
        continue match r2 {
            [{ kind: Symbol(","), .. }, .. r3] => r3
            _ => r2
          }
      }
    }
  }
  (entities, rest)
}

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

///|
fn parse_conditions(
  tokens : ArrayView[Token],
) -> (Array[@ast.Condition], ArrayView[Token]) raise ParseError {
  let conds : Array[@ast.Condition] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Keyword(When), .. }, .. rest] => {
        let (expr, rest) = parse_cond_body(rest)
        conds.push({ kind: @ast.When, body: expr })
        continue rest
      }
      [{ kind: Keyword(Unless), .. }, .. rest] => {
        let (expr, rest) = parse_cond_body(rest)
        conds.push({ kind: @ast.Unless, body: expr })
        continue rest
      }
      _ => break rest
    }
  }
  (conds, rest)
}

///|
fn parse_cond_body(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Bracket('{'), .. }, .. rest] else {
    raise ParseError("expected '{' in condition", tokens[0].pos)
  }
  let (expr, rest) = parse_expr(rest)
  if rest.length() > 0 && rest[0].kind == Bracket('}') {
    (expr, rest[1:])
  } else {
    raise ParseError(
      "expected '}' after condition",
      if rest.length() > 0 {
        rest[0].pos
      } else {
        tokens[0].pos
      },
    )
  }
}

///|
fn keyword_string(k : Keyword) -> String {
  match k {
    Permit => "permit"
    Forbid => "forbid"
    When => "when"
    Unless => "unless"
    In => "in"
    Has => "has"
    Like => "like"
    Is => "is"
    If => "if"
    Then => "then"
    Else => "else"
  }
}
