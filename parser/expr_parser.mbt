// Cedar expression parser — recursive descent with ArrayView pattern matching.
// References: cedar-policy/cedar (Rust), cedar-policy/cedar-go
//
// Precedence per Cedar spec (lowest → highest):
//   Expr  ::= Or | 'if' Expr 'then' Expr 'else' Expr
//   Or    ::= And {'||' And}
//   And   ::= Relation {'&&' Relation}
//   Rel   ::= Add [RELOP Add | 'has' I | 'like' P | 'is' Path ('in' Add)?]
//   Add   ::= Mult {('+' | '-') Mult}
//   Mult  ::= Unary {'*' Unary}
//   Unary ::= ['!' | '-']×4 Member
//   Member::= Primary {'.' IDENT ['(' Args ')'] | '[' STR ']'}

// ParseError is defined in token.mbt

// ---------------------------------------------------------------------------
// parse_expr — top-level entry
// ---------------------------------------------------------------------------

///|
pub fn parse_expr(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Keyword(If), .. }, .. rest] => {
      let (cond, rest) = parse_expr(rest)
      guard rest is [{ kind: Keyword(Then), .. }, .. r1] else {
        raise ParseError("expected 'then'", rest[0].pos)
      }
      let (then_expr, r1) = parse_expr(r1)
      guard r1 is [{ kind: Keyword(Else), .. }, .. r2] else {
        raise ParseError("expected 'else'", r1[0].pos)
      }
      let (else_expr, r2) = parse_expr(r2)
      (@ast.If(cond, then_expr, else_expr), r2)
    }
    _ => parse_or(tokens)
  }
}

// ---------------------------------------------------------------------------
// Or ::= And {'||' And}
// ---------------------------------------------------------------------------

///|
fn parse_or(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, init) = parse_and(tokens)
  let mut expr = left
  let rest = for rest = init {
    match rest {
      [{ kind: Op(Or), .. }, .. r1] => {
        let (right, r1) = parse_and(r1)
        expr = @ast.Or(expr, right)
        continue r1
      }
      _ => break rest
    }
  }
  (expr, rest)
}

// ---------------------------------------------------------------------------
// And ::= Relation {'&&' Relation}
// ---------------------------------------------------------------------------

///|
fn parse_and(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, init) = parse_relation(tokens)
  let mut expr = left
  let rest = for rest = init {
    match rest {
      [{ kind: Op(And), .. }, .. r1] => {
        let (right, r1) = parse_relation(r1)
        expr = @ast.And(expr, right)
        continue r1
      }
      _ => break rest
    }
  }
  (expr, rest)
}

// ---------------------------------------------------------------------------
// Relation ::= Add [RELOP Add | 'has' I | 'like' P | 'is' Path ('in' Add)?]
// ---------------------------------------------------------------------------

///|
fn parse_relation(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_add(tokens)
  match rest {
    [{ kind: Op(Eq), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Eq, left, right), r1)
    }
    [{ kind: Op(Ne), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Ne, left, right), r1)
    }
    [{ kind: Op(Lt), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Less, left, right), r1)
    }
    [{ kind: Op(Le), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.LessEq, left, right), r1)
    }
    [{ kind: Op(Gt), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Gt, left, right), r1)
    }
    [{ kind: Op(Ge), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Ge, left, right), r1)
    }
    [{ kind: Keyword(In), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.In_, left, right), r1)
    }
    [{ kind: Keyword(Has), .. }, .. r1] => parse_has_expr(left, r1)
    [{ kind: Keyword(Like), .. }, .. r1] => parse_like_expr(left, r1)
    [{ kind: Keyword(Is), .. }, .. r1] => parse_is_expr(left, r1)
    _ => (left, rest)
  }
}

// ---------------------------------------------------------------------------
// Add ::= Mult {('+' | '-') Mult}
// ---------------------------------------------------------------------------

///|
fn parse_add(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, init) = parse_mult(tokens)
  let mut expr = left
  let rest = for rest = init {
    match rest {
      [{ kind: Op(Add), .. }, .. r1] => {
        let (right, r1) = parse_mult(r1)
        expr = @ast.BinaryApp(@ast.Add, expr, right)
        continue r1
      }
      [{ kind: Op(Sub), .. }, .. r1] => {
        let (right, r1) = parse_mult(r1)
        expr = @ast.BinaryApp(@ast.Sub, expr, right)
        continue r1
      }
      _ => break rest
    }
  }
  (expr, rest)
}

// ---------------------------------------------------------------------------
// Mult ::= Unary {'*' Unary}
// ---------------------------------------------------------------------------

///|
fn parse_mult(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, init) = parse_unary(tokens)
  let mut expr = left
  let rest = for rest = init {
    match rest {
      [{ kind: Op(Mul), .. }, .. r1] => {
        let (right, r1) = parse_unary(r1)
        expr = @ast.BinaryApp(@ast.Mul, expr, right)
        continue r1
      }
      _ => break rest
    }
  }
  (expr, rest)
}

// ---------------------------------------------------------------------------
// Unary ::= ['!' | '-']×4 Member
// ---------------------------------------------------------------------------

///|
fn parse_unary(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Op(Not), .. }, .. rest] => {
      let (operand, rest) = parse_unary(rest)
      (@ast.UnaryApp(@ast.Not, operand), rest)
    }
    [{ kind: Op(Sub), .. }, .. rest] =>
      match rest {
        [{ kind: Int(n), .. }, .. r2] =>
          // negative literal: -N → Lit(Long(-N)), then continue member
          parse_postfix(@ast.Lit(@ast.Long(-n)), r2)
        _ => {
          let (operand, rest) = parse_unary(rest)
          (@ast.UnaryApp(@ast.Neg, operand), rest)
        }
      }
    _ => parse_member(tokens)
  }
}

// ---------------------------------------------------------------------------
// Member ::= Primary {'.' IDENT ['(' Args ')'] | '[' STR ']'}
// ---------------------------------------------------------------------------

///|
fn parse_member(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (expr, rest) = parse_primary(tokens)
  parse_postfix(expr, rest)
}

///|
fn parse_postfix(
  expr : @ast.Expr,
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Symbol("."), .. }, .. rest] => {
      guard rest is [{ kind: Ident(name), .. }, .. r2] else {
        raise ParseError("expected attribute name after dot", rest[0].pos)
      }
      match r2 {
        [{ kind: Bracket('('), .. }, .. r3] => {
          let (args, r3) = parse_arg_list(r3)
          guard r3 is [{ kind: Bracket(')'), .. }, .. r4] else {
            raise ParseError("expected ')'", r3[0].pos)
          }
          parse_postfix(make_method_call(expr, name, args), r4)
        }
        _ => parse_postfix(@ast.GetAttr(expr, name), r2)
      }
    }
    [{ kind: Bracket('['), .. }, .. rest] => {
      guard rest is [{ kind: String(s), .. }, .. r2] else {
        raise ParseError("expected string in bracket access", rest[0].pos)
      }
      guard r2 is [{ kind: Bracket(']'), .. }, .. r3] else {
        raise ParseError("expected ']'", r2[0].pos)
      }
      parse_postfix(@ast.GetAttr(expr, unescape_string(s)), r3)
    }
    _ => (expr, tokens)
  }
}

///|
fn make_method_call(
  lhs : @ast.Expr,
  method_name : String,
  args : Array[@ast.Expr],
) -> @ast.Expr {
  match method_name {
    "contains" => @ast.BinaryApp(@ast.Contains, lhs, args[0])
    "containsAll" => @ast.BinaryApp(@ast.ContainsAll, lhs, args[0])
    "containsAny" => @ast.BinaryApp(@ast.ContainsAny, lhs, args[0])
    "getTag" => @ast.GetTag(lhs, args[0])
    "hasTag" => @ast.HasTag(lhs, args[0])
    "isEmpty" => @ast.UnaryApp(@ast.IsEmpty, lhs)
    _ => @ast.ExtensionApp({ ns: [], name: method_name }, cons_expr(lhs, args))
  }
}

// ---------------------------------------------------------------------------
// Primary ::= LITERAL | VAR | Entity | '(' Expr ')' | '[' ... ']' | '{' ... '}'
// ---------------------------------------------------------------------------

///|
fn parse_primary(
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [head, .. rest] =>
      match head.kind {
        Bool(b) => (@ast.Lit(@ast.Bool(b)), rest)
        Int(n) => (@ast.Lit(@ast.Long(n)), rest)
        String(s) => (@ast.Lit(@ast.String(unescape_string(s))), rest)
        Ident("principal") => (@ast.Var(@ast.Principal), rest)
        Ident("action") => (@ast.Var(@ast.Action), rest)
        Ident("resource") => (@ast.Var(@ast.Resource), rest)
        Ident("context") => (@ast.Var(@ast.Context), rest)
        Ident(_) => parse_entity_or_extfun(head, rest)
        Bracket('(') => {
          let (expr, rest) = parse_expr(rest)
          guard rest is [{ kind: Bracket(')'), .. }, .. r2] else {
            raise ParseError("expected ')'", rest[0].pos)
          }
          (expr, r2)
        }
        Bracket('[') => {
          let (elems, rest) = parse_comma_list(rest, ']')
          (@ast.Set(elems), rest)
        }
        Bracket('{') => {
          let (entries, rest) = parse_record_body(rest)
          (@ast.Record(entries), rest)
        }
        _ => raise ParseError("unexpected token in expression", head.pos)
      }
    [] =>
      raise ParseError("unexpected end of expression", @ast.Position::{
        filename: "",
        offset: 0,
        line: 0,
        column: 0,
      })
  }
}

// ---------------------------------------------------------------------------
// Entity UID or extension function call
// ---------------------------------------------------------------------------

///|
fn parse_entity_or_extfun(
  first_tok : Token,
  rest : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard first_tok.kind is Ident(first_name) else {
    raise ParseError("expected entity or function name", first_tok.pos)
  }

  // extension function call: func(args)
  if rest.length() > 0 && rest[0].kind == Bracket('(') {
    let (args, r2) = parse_arg_list(rest[1:])
    guard r2.length() > 0 && r2[0].kind == Bracket(')') else {
      raise ParseError("expected ')'", first_tok.pos)
    }
    return (@ast.ExtensionApp({ ns: [], name: first_name }, args), r2[1:])
  }

  // entity UID: Type::...::"id"
  guard rest is [{ kind: Symbol("::"), .. }, .. r1] else {
    raise ParseError("expected '(' or '::'", rest[0].pos)
  }
  let mut path = first_name
  for rest = r1 {
    match rest {
      [{ kind: Ident(next), .. }, .. r2] => {
        path = "\{path}::\{next}"
        guard r2 is [{ kind: Symbol("::"), .. }, .. r3] else {
          raise ParseError("expected '::' in entity UID", r2[0].pos)
        }
        continue r3
      }
      [{ kind: String(id), .. }, .. r2] =>
        return (@ast.Lit(@ast.EntityUID({ type_: path, id })), r2)
      [t, ..] => raise ParseError("expected type name or id string", t.pos)
      [] => raise ParseError("unexpected end of entity UID", first_tok.pos)
    }
  }
  raise ParseError("unexpected end of entity UID", first_tok.pos)
}

// ---------------------------------------------------------------------------
// Special RHS parsers — has / like / is
// ---------------------------------------------------------------------------

///|
fn parse_has_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard tokens is [head, .. init] else {
    raise ParseError("expected attribute after 'has'", tokens[0].pos)
  }
  let first_attr = match head.kind {
    Ident(a) => a
    String(s) => unescape_string(s)
    _ => raise ParseError("expected attribute after 'has'", head.pos)
  }

  let mut result = @ast.HasAttr(lhs, first_attr)
  let mut current = @ast.GetAttr(lhs, first_attr)

  let rest = for rest = init {
    match rest {
      [{ kind: Symbol("."), .. }, .. r1] => {
        guard r1 is [{ kind: Ident(attr), .. }, .. r2] else {
          raise ParseError("expected attribute name after dot", r1[0].pos)
        }
        result = @ast.And(result, @ast.HasAttr(current, attr))
        current = @ast.GetAttr(current, attr)
        continue r2
      }
      _ => break rest
    }
  }
  (result, rest)
}

///|
fn parse_like_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: String(pat), .. }, .. r1] else {
    raise ParseError("expected string pattern after 'like'", tokens[0].pos)
  }
  let pattern = parse_pattern(pat)
  (@ast.Like(lhs, pattern), r1)
}

///|
fn parse_is_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token],
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (etype, r1) = parse_entity_type(tokens)
  match r1 {
    [{ kind: Keyword(In), .. }, .. r2] => {
      let (in_entity, r2) = parse_add(r2)
      let is_expr = @ast.Expr::Is(lhs, etype)
      (
        @ast.And(
          is_expr,
          @ast.BinaryApp(@ast.In_, @ast.Expr::Is(lhs, etype), in_entity),
        ),
        r2,
      )
    }
    _ => (@ast.Expr::Is(lhs, etype), r1)
  }
}

// ---------------------------------------------------------------------------
// List / record / argument parsers
// ---------------------------------------------------------------------------

///|
fn parse_arg_list(
  tokens : ArrayView[Token],
) -> (Array[@ast.Expr], ArrayView[Token]) raise ParseError {
  let args : Array[@ast.Expr] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Bracket(')'), .. }, ..] => break rest
      _ => {
        let (arg, r2) = parse_expr(rest)
        args.push(arg)
        continue match r2 {
            [{ kind: Symbol(","), .. }, .. r3] => r3
            _ => r2
          }
      }
    }
  }
  (args, rest)
}

///|
fn parse_comma_list(
  tokens : ArrayView[Token],
  end_bracket : Char,
) -> (Array[@ast.Expr], ArrayView[Token]) raise ParseError {
  let exprs : Array[@ast.Expr] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Bracket(b), .. }, .. r1] if b == end_bracket => break r1
      _ => {
        let (expr, r2) = parse_expr(rest)
        exprs.push(expr)
        continue match r2 {
            [{ kind: Symbol(","), .. }, .. r3] => r3
            _ => r2
          }
      }
    }
  }
  (exprs, rest)
}

///|
fn parse_record_body(
  tokens : ArrayView[Token],
) -> (Array[(String, @ast.Expr)], ArrayView[Token]) raise ParseError {
  let entries : Array[(String, @ast.Expr)] = []
  let rest = for rest = tokens {
    match rest {
      [{ kind: Bracket('}'), .. }, .. r1] => break r1
      [head, .. r2] => {
        let key = match head.kind {
          Ident(k) => k
          String(s) => unescape_string(s)
          _ => raise ParseError("expected record key", head.pos)
        }
        guard r2 is [{ kind: Symbol(":"), .. }, .. r3] else {
          raise ParseError("expected ':'", r2[0].pos)
        }
        let (value, r4) = parse_expr(r3)
        entries.push((key, value))
        continue match r4 {
            [{ kind: Symbol(","), .. }, .. r5] => r5
            _ => r4
          }
      }
      [] =>
        raise ParseError("expected '}'", @ast.Position::{
          filename: "",
          offset: 0,
          line: 0,
          column: 0,
        })
    }
  }
  (entries, rest)
}

// ---------------------------------------------------------------------------
// Entity type path
// ---------------------------------------------------------------------------

///|
fn parse_entity_type(
  tokens : ArrayView[Token],
) -> (@ast.EntityType, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident(first), .. }, .. r1] else {
    raise ParseError("expected entity type", tokens[0].pos)
  }
  let mut path = first
  let rest = for rest = r1 {
    match rest {
      [{ kind: Symbol("::"), .. }, .. r2] => {
        guard r2 is [{ kind: Ident(next), .. }, .. r3] else {
          raise ParseError("expected type name after ::", r2[0].pos)
        }
        path = "\{path}::\{next}"
        continue r3
      }
      _ => break rest
    }
  }
  (@ast.EntityType(path), rest)
}

// ---------------------------------------------------------------------------
// Helpers — pattern, unescape, cons
// ---------------------------------------------------------------------------

///|
fn parse_pattern(raw : String) -> @ast.Pattern {
  let elems : Array[@ast.PatternElem] = []
  for rest = raw[:] {
    match rest {
      ['*', .. rest] => {
        elems.push(@ast.Wildcard)
        continue rest
      }
      ['\\', c, .. rest] => {
        let ch = match c {
          'n' => '\n'
          'r' => '\r'
          't' => '\t'
          _ => c
        }
        elems.push(@ast.Char(ch))
        continue rest
      }
      [c, .. rest] => {
        elems.push(@ast.Char(c))
        continue rest
      }
      [] => break
    }
  }
  { elements: elems }
}

///|
fn unescape_string(s : String) -> String {
  let mut buf = ""
  for rest = s[:] {
    match rest {
      ['\\', c, .. rest] => {
        let ch = match c {
          'n' => "\n"
          'r' => "\r"
          't' => "\t"
          '\\' => "\\"
          '"' => "\""
          '\'' => "'"
          '*' => "*"
          '0' => "\u0000"
          _ => c.to_string()
        }
        buf = buf + ch
        continue rest
      }
      [c, .. rest] => {
        buf = buf + c.to_string()
        continue rest
      }
      [] => break
    }
  }
  buf
}

///|
fn[T] cons_expr(x : T, xs : Array[T]) -> Array[T] {
  let result : Array[T] = [x]
  for i = 0; i < xs.length(); i = i + 1 {
    result.push(xs[i])
  }
  result
}
