// Cedar AST → source text (stringify / marshal).
// Inverse of parsing: takes AST nodes and produces valid Cedar source.
// Precedence-based parenthesization keeps output minimal.
// Reference: cedar-go/internal/parser/cedar_marshal.go

// ---------------------------------------------------------------------------
// Precedence levels (higher = binds tighter)
// ---------------------------------------------------------------------------

///|
fn expr_prec(expr : @ast.Expr) -> Int {
  match expr {
    @ast.If(_, _, _) => 1
    @ast.Or(_, _) => 2
    @ast.And(_, _) => 3
    @ast.HasAttr(_, _)
    | @ast.Like(_, _)
    | @ast.Is(_, _)
    | @ast.GetTag(_, _)
    | @ast.HasTag(_, _) => 4
    @ast.BinaryApp(op, _, _) => binary_prec(op)
    @ast.UnaryApp(_, _) => 7
    _ => 8
  }
}

///|
fn binary_prec(op : @ast.BinaryOp) -> Int {
  match op {
    @ast.Eq | @ast.Ne | @ast.Less | @ast.LessEq => 4
    @ast.Gt | @ast.Ge | @ast.In_ => 4
    @ast.Contains | @ast.ContainsAll | @ast.ContainsAny => 4
    @ast.Add | @ast.Sub => 5
    @ast.Mul => 6
  }
}

///|
fn need_parens(inner_prec : Int, outer_prec : Int, is_right : Bool) -> Bool {
  inner_prec < outer_prec || (is_right && inner_prec == outer_prec)
}

///|
fn paren(
  s : String,
  inner_prec : Int,
  outer_prec : Int,
  is_right : Bool,
) -> String {
  if need_parens(inner_prec, outer_prec, is_right) {
    "(" + s + ")"
  } else {
    s
  }
}

// ---------------------------------------------------------------------------
// Keyword / ident helpers
// ---------------------------------------------------------------------------

///|
fn is_reserved(s : String) -> Bool {
  match s {
    "permit" | "forbid" | "when" | "unless" => true
    "in" | "has" | "like" | "is" => true
    "if" | "then" | "else" => true
    "true" | "false" => true
    "principal" | "action" | "resource" | "context" => true
    _ => false
  }
}

///|
fn is_valid_ident(s : String) -> Bool {
  if s == "" || is_reserved(s) {
    return false
  }
  // First character: [a-zA-Z_]  (ASCII 65-90, 97-122, 95)
  let first = s[0]
  if !(first >= 65 && first <= 90) &&
    !(first >= 97 && first <= 122) &&
    first != 95 {
    return false
  }
  // Rest: [a-zA-Z0-9_]*  (ASCII 48-57, 65-90, 97-122, 95)
  for i = 1; i < s.length(); i = i + 1 {
    let c = s[i]
    if !(c >= 48 && c <= 57) &&
      !(c >= 65 && c <= 90) &&
      !(c >= 97 && c <= 122) &&
      c != 95 {
      return false
    }
  }
  true
}

///|
fn ident_str(s : String) -> String {
  if is_valid_ident(s) {
    s
  } else {
    "\"" + s + "\""
  }
}

// ---------------------------------------------------------------------------
// Literal → Cedar source
// ---------------------------------------------------------------------------

///|
fn literal_str(l : @ast.Literal) -> String {
  match l {
    @ast.Bool(true) => "true"
    @ast.Bool(false) => "false"
    @ast.Long(v) => v.to_string()
    @ast.String(v) => "\"" + v + "\""
    @ast.EntityUID(uid) => uid.type_ + "::\"" + uid.id + "\""
  }
}

// ---------------------------------------------------------------------------
// BinaryOp → (symbol, is_method_call)
// ---------------------------------------------------------------------------

///|
fn binary_sym(op : @ast.BinaryOp) -> (String, Bool) {
  match op {
    @ast.Eq => ("==", false)
    @ast.Ne => ("!=", false)
    @ast.Less => ("<", false)
    @ast.LessEq => ("<=", false)
    @ast.Gt => (">", false)
    @ast.Ge => (">=", false)
    @ast.Add => ("+", false)
    @ast.Sub => ("-", false)
    @ast.Mul => ("*", false)
    @ast.In_ => ("in", false)
    @ast.Contains => (".contains", true)
    @ast.ContainsAll => (".containsAll", true)
    @ast.ContainsAny => (".containsAny", true)
  }
}

// ---------------------------------------------------------------------------
// Pattern → Cedar source
// ---------------------------------------------------------------------------

///|
fn pattern_str(p : @ast.Pattern) -> String {
  let mut out = "\""
  for elem in p.elements {
    match elem {
      @ast.Char(c) => out = out + c.to_string()
      @ast.Wildcard => out = out + "*"
    }
  }
  out + "\""
}

// ---------------------------------------------------------------------------
// Name → Cedar source
// ---------------------------------------------------------------------------

///|
fn name_str(n : @ast.Name) -> String {
  if n.ns.length() == 0 {
    n.name
  } else {
    let mut out = ""
    for seg in n.ns {
      out = out + seg + "::"
    }
    out + n.name
  }
}

// ---------------------------------------------------------------------------
// Scope constraint → Cedar source
// ---------------------------------------------------------------------------

///|
fn scope_str(sc : @ast.ScopeConstraint) -> String {
  match sc {
    @ast.All => ""
    @ast.Eq(uid) => " == " + uid.type_ + "::\"" + uid.id + "\""
    @ast.In(uid) => " in " + uid.type_ + "::\"" + uid.id + "\""
    @ast.Is(ty) => " is " + ty.0
    @ast.IsIn(ty, uid) =>
      " is " + ty.0 + " in " + uid.type_ + "::\"" + uid.id + "\""
    @ast.InSet(entities) => {
      let mut out = " in ["
      for i = 0; i < entities.length(); i = i + 1 {
        if i > 0 {
          out = out + ", "
        }
        out = out + entities[i].type_ + "::\"" + entities[i].id + "\""
      }
      out + "]"
    }
  }
}

///|
fn scope_multiline(sc : @ast.ScopeConstraint) -> Bool {
  match sc {
    @ast.All => false
    _ => true
  }
}

// ---------------------------------------------------------------------------
// Annotation → Cedar source
// ---------------------------------------------------------------------------

///|
fn annotation_str(ann : @ast.Annotation) -> String {
  if ann.value == "" {
    "@" + ann.key
  } else {
    "@" + ann.key + "(\"" + ann.value + "\")"
  }
}

// ---------------------------------------------------------------------------
// Core expression formatting (recursive, precedence-aware).
// `is_right`: true when this expr is the right operand of a left-assoc
// binary operator, forcing parens at equal precedence.
// ---------------------------------------------------------------------------

///|
fn format_expr_inner(
  e : @ast.Expr,
  outer_prec : Int,
  is_right : Bool,
) -> String {
  let p = expr_prec(e)
  match e {
    @ast.Lit(l) => literal_str(l)
    @ast.Var(@ast.Principal) => "principal"
    @ast.Var(@ast.Action) => "action"
    @ast.Var(@ast.Resource) => "resource"
    @ast.Var(@ast.Context) => "context"
    @ast.GetAttr(inner_e, attr) => {
      let inner = format_expr_inner(inner_e, 8, false)
      if is_valid_ident(attr) {
        inner + "." + attr
      } else {
        inner + "[\"" + attr + "\"]"
      }
    }
    @ast.Set(elems) => {
      let mut out = "["
      for i = 0; i < elems.length(); i = i + 1 {
        if i > 0 {
          out = out + ", "
        }
        out = out + format_expr_inner(elems[i], 0, false)
      }
      out + "]"
    }
    @ast.Record(pairs) => {
      let mut out = "{"
      for i = 0; i < pairs.length(); i = i + 1 {
        let (k, v) = pairs[i]
        if i > 0 {
          out = out + ", "
        }
        out = out + ident_str(k) + ": " + format_expr_inner(v, 0, false)
      }
      out + "}"
    }
    @ast.ExtensionApp(name, args) => {
      let mut out = name_str(name) + "("
      for i = 0; i < args.length(); i = i + 1 {
        if i > 0 {
          out = out + ", "
        }
        out = out + format_expr_inner(args[i], 0, false)
      }
      out + ")"
    }
    @ast.Slot(v) => "?" + v
    @ast.Unknown(v, _) => v
    @ast.If(c, t, el) => {
      let inner = "if " +
        format_expr_inner(c, 0, false) +
        " then " +
        format_expr_inner(t, 0, false) +
        " else " +
        format_expr_inner(el, 0, false)
      paren(inner, p, outer_prec, is_right)
    }
    @ast.And(l, r) => {
      let left = format_expr_inner(l, p, false)
      let right = format_expr_inner(r, p, true)
      paren(left + " && " + right, p, outer_prec, is_right)
    }
    @ast.Or(l, r) => {
      let left = format_expr_inner(l, p, false)
      let right = format_expr_inner(r, p, true)
      paren(left + " || " + right, p, outer_prec, is_right)
    }
    @ast.HasAttr(he, attr) => {
      let inner = format_expr_inner(he, p, false) + " has " + ident_str(attr)
      paren(inner, p, outer_prec, is_right)
    }
    @ast.Like(le, pat) => {
      let inner = format_expr_inner(le, p, false) + " like " + pattern_str(pat)
      paren(inner, p, outer_prec, is_right)
    }
    @ast.Is(ie, ty) => {
      let inner = format_expr_inner(ie, p, false) + " is " + ty.0
      paren(inner, p, outer_prec, is_right)
    }
    @ast.GetTag(ge, tag) => {
      let inner = format_expr_inner(ge, p, false) +
        ".getTag(" +
        format_expr_inner(tag, 0, false) +
        ")"
      paren(inner, p, outer_prec, is_right)
    }
    @ast.HasTag(he, tag) => {
      let inner = format_expr_inner(he, p, false) +
        ".hasTag(" +
        format_expr_inner(tag, 0, false) +
        ")"
      paren(inner, p, outer_prec, is_right)
    }
    @ast.BinaryApp(op, left, right) => {
      let (sym, is_method) = binary_sym(op)
      if is_method {
        let inner = format_expr_inner(left, 8, false) +
          sym +
          "(" +
          format_expr_inner(right, 0, false) +
          ")"
        paren(inner, p, outer_prec, is_right)
      } else {
        let l = format_expr_inner(left, p, false)
        let r = format_expr_inner(right, p, true)
        paren(l + " " + sym + " " + r, p, outer_prec, is_right)
      }
    }
    @ast.UnaryApp(@ast.Not, ne) => {
      let inner = "!" + format_expr_inner(ne, p, false)
      paren(inner, p, outer_prec, is_right)
    }
    @ast.UnaryApp(@ast.Neg, nge) => {
      let inner = "-" + format_expr_inner(nge, p, false)
      paren(inner, p, outer_prec, is_right)
    }
    @ast.UnaryApp(@ast.IsEmpty, iee) => {
      let inner = format_expr_inner(iee, 8, false) + ".isEmpty()"
      paren(inner, p, outer_prec, is_right)
    }
  }
}

// ---------------------------------------------------------------------------
// Condition → Cedar source
// ---------------------------------------------------------------------------

///|
fn condition_str(cond : @ast.Condition) -> String {
  let kw = match cond.kind {
    @ast.When => "when"
    @ast.Unless => "unless"
  }
  kw + " { " + format_expr_inner(cond.body, 0, false) + " }"
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Convert Expr to Cedar source text.
pub fn stringify_expr(e : @ast.Expr) -> String {
  format_expr_inner(e, 0, false)
}

///|
/// Convert Policy to Cedar source text.
pub fn stringify(p : @ast.Policy) -> String {
  let mut s = ""

  for ann in p.annotations {
    s = s + annotation_str(ann) + "\n"
  }

  let eff = match p.effect {
    @ast.Permit => "permit"
    @ast.Forbid => "forbid"
  }

  let ml = scope_multiline(p.principal) ||
    scope_multiline(p.action) ||
    scope_multiline(p.resource)
  if ml {
    s = s + eff + "(\n"
    s = s + "  principal" + scope_str(p.principal) + ",\n"
    s = s + "  action" + scope_str(p.action) + ",\n"
    s = s + "  resource" + scope_str(p.resource) + "\n"
    s = s + ")"
  } else {
    s = s + eff + "(principal, action, resource)"
  }

  for cond in p.conditions {
    s = s + "\n" + condition_str(cond)
  }

  s + ";"
}
