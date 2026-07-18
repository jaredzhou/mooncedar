// Pattern matching for the `like` operator (IAM StringLike semantics).
// Reference: cedar-policy-core/src/evaluator.rs — wildcard_match

///|
/// Match a string against a Cedar like-pattern.
/// `*` matches any sequence of characters (including empty).
/// `\*` matches a literal `*` (already parsed as PatternElem::Char('*')).
///
/// Uses two-pointer backtracking: on Wildcard, record the star position
/// and advance the text pointer; on mismatch, backtrack to the last star.
pub fn wildcard_match(text : String, pattern : @ast.Pattern) -> Bool {
  let chars = text.iter().to_array()
  let elems = pattern.elements
  let t_len = chars.length()
  let p_len = elems.length()

  let mut t = 0
  let mut p = 0

  // Backtracking state: pattern index after last Wildcard, matched text offset
  let mut star_idx = -1
  let mut match_idx = 0

  while t < t_len {
    // Encounter `*` — record position and skip
    if p < p_len && elems[p] == @ast.PatternElem::Wildcard {
      star_idx = p
      match_idx = t
      p += 1
      continue
    }

    // Try literal char match
    if p < p_len {
      match elems[p] {
        @ast.PatternElem::Char(c) =>
          if chars[t] == c {
            t += 1
            p += 1
            continue
          }
        _ => ()
      }
    }

    // Mismatch — backtrack to last `*`
    if star_idx >= 0 {
      match_idx += 1
      t = match_idx
      p = star_idx + 1
      continue
    }

    return false
  }

  // Remaining pattern elements must all be `*`
  while p < p_len {
    if elems[p] != @ast.PatternElem::Wildcard {
      return false
    }
    p += 1
  }

  true
}
