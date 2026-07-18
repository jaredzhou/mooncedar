// Cedar lexer — functional tokenizer using StringView pattern matching.
// Reference: BuildYourOwnMBT lexer style

///|
pub(all) suberror ParseError {
  ParseError(String, @ast.Position)
} derive(Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  pos : @ast.Position
} derive(Debug, Eq)

///|
pub fn Token::new(kind : TokenKind, pos : @ast.Position) -> Token {
  { kind, pos }
}

///|
pub(all) enum TokenKind {
  // Literals
  Bool(Bool)
  Int(Int64)
  String(String)

  // Identifiers (lowercase & uppercase — Cedar doesn't distinguish)
  Ident(String)

  // Reserved keywords (Rust: dedicated tokens; Go: TokenReservedKeyword)
  Keyword(Keyword)

  // Operators
  Op(Operator)

  // Structure
  Bracket(Char) // (, ), {, }, [, ]
  Symbol(String) // ., ,, ;, :, ::, @
  Unknown // unexpected characters (for error recovery)
  EOF
} derive(Debug, Eq)

///|
/// Reserved keywords — matched by the lexer before user identifiers.
/// `principal`/`action`/`resource`/`context` are NOT keywords;
/// they are `Lower(...)` since they can appear as user identifiers.
pub(all) enum Keyword {
  // Effects
  Permit
  Forbid
  // Conditions
  When
  Unless
  // Expression operators / scope
  In
  Has
  Like
  Is
  // Conditional
  If
  Then
  Else
} derive(Debug, Eq)

///|
/// Manually implement Show for Keyword.
pub impl Show for Keyword with fn output(self, logger) {
  match self {
    Permit => logger.write_string("Permit")
    Forbid => logger.write_string("Forbid")
    When => logger.write_string("When")
    Unless => logger.write_string("Unless")
    In => logger.write_string("In")
    Has => logger.write_string("Has")
    Like => logger.write_string("Like")
    Is => logger.write_string("Is")
    If => logger.write_string("If")
    Then => logger.write_string("Then")
    Else => logger.write_string("Else")
  }
}

//

///|
pub impl Show for TokenKind with fn output(self, logger) {
  match self {
    Bool(b) => {
      logger.write_string("Bool(")
      logger.write_string(b.to_string())
      logger.write_string(")")
    }
    Int(n) => {
      logger.write_string("Int(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
    String(s) => {
      logger.write_string("String(")
      logger.write_string(s)
      logger.write_string(")")
    }
    Ident(s) => {
      logger.write_string("Ident(")
      logger.write_string(s)
      logger.write_string(")")
    }
    Keyword(k) => {
      logger.write_string("Keyword(")
      logger.write_string(k.to_string())
      logger.write_string(")")
    }
    Op(op) => {
      logger.write_string("Op(")
      logger.write_string(op.to_string())
      logger.write_string(")")
    }
    Bracket(c) => {
      logger.write_string("Bracket(")
      logger.write_string(c.to_string())
      logger.write_string(")")
    }
    Symbol(s) => {
      logger.write_string("Symbol(")
      logger.write_string(s)
      logger.write_string(")")
    }
    Unknown => logger.write_string("Unknown")
    EOF => logger.write_string("EOF")
  }
}

///|
pub(all) enum Operator {
  Add // +
  Sub // -
  Mul // *
  Eq // ==
  Ne // !=
  Lt // <
  Gt // >
  Le // <=
  Ge // >=
  And // &&
  Or // ||
  Not // !
} derive(Debug, Eq)

///|
/// Manually implement Show for Operator.
pub impl Show for Operator with fn output(self, logger) {
  let s = match self {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Eq => "=="
    Ne => "!="
    Lt => "<"
    Gt => ">"
    Le => "<="
    Ge => ">="
    And => "&&"
    Or => "||"
    Not => "!"
  }
  logger.write_string(s)
}

// ---------------------------------------------------------------------------
// Lexer helpers
// ---------------------------------------------------------------------------

///|
/// Collect a lowercase or uppercase identifier from a StringView.
fn collect_ident(s : StringView, acc : String) -> (String, StringView) {
  match s {
    [] => (acc, s)
    [c, .. rest] =>
      if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' {
        collect_ident(rest, acc + c.to_string())
      } else {
        (acc, s)
      }
  }
}

///|
/// Collect digits from a StringView.
fn collect_digits(s : StringView, acc : String) -> (String, StringView) {
  match s {
    [] => (acc, s)
    [c, .. rest] =>
      if c >= '0' && c <= '9' {
        collect_digits(rest, acc + c.to_string())
      } else {
        (acc, s)
      }
  }
}

///|
/// Skip a line comment (// to end of line).
fn skip_line_comment(s : StringView) -> StringView {
  match s {
    [] => s
    ['\n', .. rest] => rest
    [_, .. rest] => skip_line_comment(rest)
  }
}

///|
/// Skip a block comment (/* to */).
fn skip_block_comment(s : StringView) -> StringView {
  match s {
    [] => s
    ['*', '/', .. rest] => rest
    [_, .. rest] => skip_block_comment(rest)
  }
}

///|
/// Collect a string literal (including escape sequences, stored raw).
fn collect_string(s : StringView, acc : String) -> (String, StringView) {
  match s {
    [] => (acc, s)
    ['"', .. rest] => (acc, rest)
    ['\\', '"', .. rest] => collect_string(rest, acc + "\\\"")
    ['\\', '\\', .. rest] => collect_string(rest, acc + "\\\\")
    ['\\', 'n', .. rest] => collect_string(rest, acc + "\\n")
    ['\\', 't', .. rest] => collect_string(rest, acc + "\\t")
    ['\\', 'r', .. rest] => collect_string(rest, acc + "\\r")
    ['\\', x, .. rest] =>
      // pass through other escapes raw (x, u, etc.)
      collect_string(rest, acc + "\\" + x.to_string())
    [c, .. rest] => collect_string(rest, acc + c.to_string())
  }
}

// ---------------------------------------------------------------------------
// Tokenizer entry point
// ---------------------------------------------------------------------------

///|
pub fn tokenize(code : String, filename? : String) -> Array[Token] {
  let tokens = Array::new()
  let mut line : Int = 1
  let mut col : Int = 1
  let mut offset : Int = 0

  for s = code[:] {
    match s {
      // whitespace
      [' ', .. rest] => {
        col = col + 1
        offset = offset + 1
        continue rest
      }
      ['\t', .. rest] => {
        col = col + 1
        offset = offset + 1
        continue rest
      }
      ['\r', .. rest] => {
        offset = offset + 1
        continue rest
      }
      ['\n', .. rest] => {
        line = line + 1
        col = 1
        offset = offset + 1
        continue rest
      }

      // comments
      [.. "//", .. rest] => {
        offset = offset + 2
        col = col + 2
        continue skip_line_comment(rest)
      }
      [.. "/*", .. rest] => {
        offset = offset + 2
        col = col + 2
        continue skip_block_comment(rest)
      }
      [] => {
        tokens.push(Token::new(EOF, file_pos(filename, line, col, offset)))
        break
      }

      // string literal
      ['"', .. rest] => {
        let pos = file_pos(filename, line, col, offset)
        let (str, rest_after_str) = collect_string(rest, "")
        tokens.push(Token::new(String(str), pos))
        offset = offset + 2 + str.length() // opening + closing quotes + content
        col = col + 2 + str.length()
        continue rest_after_str
      }

      // multi-char operators (before single-char!)
      [.. "::", .. rest] => {
        tokens.push(
          Token::new(Symbol("::"), file_pos(filename, line, col, offset)),
        )
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. "==", .. rest] => {
        tokens.push(Token::new(Op(Eq), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. "!=", .. rest] => {
        tokens.push(Token::new(Op(Ne), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. "<=", .. rest] => {
        tokens.push(Token::new(Op(Le), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. ">=", .. rest] => {
        tokens.push(Token::new(Op(Ge), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. "&&", .. rest] => {
        tokens.push(Token::new(Op(And), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }
      [.. "||", .. rest] => {
        tokens.push(Token::new(Op(Or), file_pos(filename, line, col, offset)))
        offset = offset + 2
        col = col + 2
        continue rest
      }

      // single-char operators
      [.. "+", .. rest] => {
        tokens.push(Token::new(Op(Add), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. "-", .. rest] => {
        tokens.push(Token::new(Op(Sub), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. "*", .. rest] => {
        tokens.push(Token::new(Op(Mul), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. "<", .. rest] => {
        tokens.push(Token::new(Op(Lt), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. ">", .. rest] => {
        tokens.push(Token::new(Op(Gt), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. "!", .. rest] => {
        tokens.push(Token::new(Op(Not), file_pos(filename, line, col, offset)))
        offset = offset + 1
        col = col + 1
        continue rest
      }

      // brackets
      ['(', .. rest] => {
        tokens.push(
          Token::new(Bracket('('), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [')', .. rest] => {
        tokens.push(
          Token::new(Bracket(')'), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      ['{', .. rest] => {
        tokens.push(
          Token::new(Bracket('{'), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      ['}', .. rest] => {
        tokens.push(
          Token::new(Bracket('}'), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      ['[', .. rest] => {
        tokens.push(
          Token::new(Bracket('['), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [']', .. rest] => {
        tokens.push(
          Token::new(Bracket(']'), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }

      // symbols
      [.. ".", .. rest] => {
        tokens.push(
          Token::new(Symbol("."), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. ",", .. rest] => {
        tokens.push(
          Token::new(Symbol(","), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. ";", .. rest] => {
        tokens.push(
          Token::new(Symbol(";"), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. ":", .. rest] => {
        tokens.push(
          Token::new(Symbol(":"), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }
      [.. "@", .. rest] => {
        tokens.push(
          Token::new(Symbol("@"), file_pos(filename, line, col, offset)),
        )
        offset = offset + 1
        col = col + 1
        continue rest
      }

      // numbers
      ['0'..='9', ..] as s => {
        let pos = file_pos(filename, line, col, offset)
        let (num_str, rest_after_num) = collect_digits(s, "")
        let count = num_str.length()
        offset = offset + count
        col = col + count
        let int_val = parse_int_string(num_str)
        tokens.push(Token::new(Int(int_val), pos))
        continue rest_after_num
      }

      // lowercase identifiers & keywords (start with lowercase letter or underscore)
      ['a'..='z' | '_', ..] as s => {
        let pos = file_pos(filename, line, col, offset)
        let (ident, rest_after_ident) = collect_ident(s, "")
        let count = ident.length()
        offset = offset + count
        col = col + count
        match ident {
          "true" => tokens.push(Token::new(Bool(true), pos))
          "false" => tokens.push(Token::new(Bool(false), pos))
          "permit" => tokens.push(Token::new(Keyword(Permit), pos))
          "forbid" => tokens.push(Token::new(Keyword(Forbid), pos))
          "when" => tokens.push(Token::new(Keyword(When), pos))
          "unless" => tokens.push(Token::new(Keyword(Unless), pos))
          "in" => tokens.push(Token::new(Keyword(In), pos))
          "has" => tokens.push(Token::new(Keyword(Has), pos))
          "like" => tokens.push(Token::new(Keyword(Like), pos))
          "is" => tokens.push(Token::new(Keyword(Is), pos))
          "if" => tokens.push(Token::new(Keyword(If), pos))
          "then" => tokens.push(Token::new(Keyword(Then), pos))
          "else" => tokens.push(Token::new(Keyword(Else), pos))
          _ => tokens.push(Token::new(Ident(ident), pos))
        }
        continue rest_after_ident
      }

      // uppercase identifiers (entity type names)
      ['A'..='Z', ..] as s => {
        let pos = file_pos(filename, line, col, offset)
        let (ident, rest_after_ident) = collect_ident(s, "")
        let count = ident.length()
        offset = offset + count
        col = col + count
        tokens.push(Token::new(Ident(ident), pos))
        continue rest_after_ident
      }

      // unknown / unexpected character — produce Unknown token for error recovery
      [_, .. rest] => {
        let pos = file_pos(filename, line, col, offset)
        tokens.push(Token::new(Unknown, pos))
        offset = offset + 1
        col = col + 1
        continue rest
      }
    }
  }
  tokens
}

///|
fn file_pos(
  filename : String?,
  line : Int,
  col : Int,
  offset : Int,
) -> @ast.Position {
  {
    filename: match filename {
      None => ""
      Some(v) => v
    },
    offset,
    line,
    column: col,
  }
}

///|
/// Parse a string of digits into Int64.
fn parse_int_string(s : String) -> Int64 {
  let mut result : Int64 = 0L
  let chars = s.iter().to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let digit = chars[i].to_int() - 48 // '0' == 48
    result = result * 10L + digit.to_int64()
  }
  result
}
