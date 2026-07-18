// Concrete operator evaluation — unary_op and binary_op.
// Reference: cedar-policy-core/src/evaluator.rs

///|
/// Evaluate a unary operator on a concrete value.
pub fn eval_unary(
  op : @ast.UnaryOp,
  arg : @ast.Value,
) -> @ast.Value raise EvalError {
  match op {
    @ast.UnaryOp::Not =>
      match arg {
        @ast.Value::Bool(b) => @ast.Value::Bool(!b)
        _ => raise TypeMismatch("Not requires Bool argument")
      }
    @ast.UnaryOp::Neg =>
      match arg {
        @ast.Value::Long(n) =>
          // 0 - n with overflow check (min_value negation overflows)
          sub_long(@ast.Value::Long(0L), @ast.Value::Long(n))
        _ => raise TypeMismatch("Neg requires Long argument")
      }
    @ast.UnaryOp::IsEmpty =>
      match arg {
        @ast.Value::Set(arr) => @ast.Value::Bool(arr.length() == 0)
        @ast.Value::Record(map) => {
          let empty : Map[String, @ast.Value] = Map([])
          @ast.Value::Bool(map == empty)
        }
        _ => raise TypeMismatch("IsEmpty requires Set or Record argument")
      }
  }
}

///|
/// Evaluate a binary operator on two concrete values.
/// Does NOT handle In_ — that requires EntityStore access
/// and is handled in expr_eval.mbt.
pub fn eval_binary(
  op : @ast.BinaryOp,
  lhs : @ast.Value,
  rhs : @ast.Value,
) -> @ast.Value raise EvalError {
  match op {
    @ast.BinaryOp::Eq => @ast.Value::Bool(lhs == rhs)
    @ast.BinaryOp::Ne => @ast.Value::Bool(!(lhs == rhs))
    @ast.BinaryOp::Less => compare_long(lhs, rhs, fn(a, b) { a < b }, "<")
    @ast.BinaryOp::LessEq => compare_long(lhs, rhs, fn(a, b) { a <= b }, "<=")
    @ast.BinaryOp::Gt => compare_long(lhs, rhs, fn(a, b) { a > b }, ">")
    @ast.BinaryOp::Ge => compare_long(lhs, rhs, fn(a, b) { a >= b }, ">=")
    @ast.BinaryOp::Add => add_long(lhs, rhs)
    @ast.BinaryOp::Sub => sub_long(lhs, rhs)
    @ast.BinaryOp::Mul => mul_long(lhs, rhs)
    @ast.BinaryOp::In_ =>
      raise InvalidOperator("In_ requires EntityStore — handle in expr_eval")
    @ast.BinaryOp::Contains => eval_contains(lhs, rhs)
    @ast.BinaryOp::ContainsAll => eval_contains_all(lhs, rhs)
    @ast.BinaryOp::ContainsAny => eval_contains_any(lhs, rhs)
  }
}

// ---------------------------------------------------------------------------
// Comparison helpers
// ---------------------------------------------------------------------------

///|
fn compare_long(
  lhs : @ast.Value,
  rhs : @ast.Value,
  cmp : (Int64, Int64) -> Bool,
  op_name : String,
) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Long(a), @ast.Value::Long(b)) => @ast.Value::Bool(cmp(a, b))
    _ => raise TypeMismatch("\{op_name} requires Long arguments")
  }
}

// ---------------------------------------------------------------------------
// Arithmetic helpers (checked)
// ---------------------------------------------------------------------------

///|
fn add_long(lhs : @ast.Value, rhs : @ast.Value) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Long(a), @ast.Value::Long(b)) => {
      let result = a + b
      if (a > 0L && b > 0L && result < 0L) || (a < 0L && b < 0L && result > 0L) {
        raise IntegerOverflow
      }
      @ast.Value::Long(result)
    }
    _ => raise TypeMismatch("+ requires Long arguments")
  }
}

///|
pub fn sub_long(
  lhs : @ast.Value,
  rhs : @ast.Value,
) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Long(a), @ast.Value::Long(b)) => {
      let result = a - b
      if (a > 0L && b < 0L && result < 0L) || (a < 0L && b > 0L && result > 0L) {
        raise IntegerOverflow
      }
      @ast.Value::Long(result)
    }
    _ => raise TypeMismatch("- requires Long arguments")
  }
}

///|
fn mul_long(lhs : @ast.Value, rhs : @ast.Value) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Long(a), @ast.Value::Long(b)) => {
      if a == 0L || b == 0L {
        return @ast.Value::Long(0L)
      }
      let result = a * b
      if result / b != a {
        raise IntegerOverflow
      }
      @ast.Value::Long(result)
    }
    _ => raise TypeMismatch("* requires Long arguments")
  }
}

// ---------------------------------------------------------------------------
// Set operations
// ---------------------------------------------------------------------------

///|
/// .contains(elem) — elem in set
fn eval_contains(
  lhs : @ast.Value,
  rhs : @ast.Value,
) -> @ast.Value raise EvalError {
  match lhs {
    @ast.Value::Set(arr) => @ast.Value::Bool(arr.contains(rhs))
    _ => raise TypeMismatch(".contains requires Set operand")
  }
}

///|
/// .containsAll(rhs) — all rhs elements are in lhs
fn eval_contains_all(
  lhs : @ast.Value,
  rhs : @ast.Value,
) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Set(lhs_arr), @ast.Value::Set(rhs_arr)) => {
      for elem in rhs_arr {
        if !lhs_arr.contains(elem) {
          return @ast.Value::Bool(false)
        }
      }
      @ast.Value::Bool(true)
    }
    _ => raise TypeMismatch(".containsAll requires Set operands")
  }
}

///|
/// .containsAny(rhs) — at least one rhs element is in lhs
fn eval_contains_any(
  lhs : @ast.Value,
  rhs : @ast.Value,
) -> @ast.Value raise EvalError {
  match (lhs, rhs) {
    (@ast.Value::Set(lhs_arr), @ast.Value::Set(rhs_arr)) => {
      for elem in rhs_arr {
        if lhs_arr.contains(elem) {
          return @ast.Value::Bool(true)
        }
      }
      @ast.Value::Bool(false)
    }
    _ => raise TypeMismatch(".containsAny requires Set operands")
  }
}
