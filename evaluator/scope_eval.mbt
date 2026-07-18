// Scope evaluation — scope_match and hierarchy traversal.
// Reference: cedar-policy-core/src/evaluator.rs

///|
/// Check whether a scope constraint matches the given entity variable.
pub fn[S : EntityStore] scope_match(
  sc : @ast.ScopeConstraint,
  uid : @ast.EntityUID,
  store : S,
) -> Bool {
  match sc {
    @ast.ScopeConstraint::All => true
    @ast.ScopeConstraint::Eq(euid) => uid == euid
    @ast.ScopeConstraint::In(parent) => is_descendant(uid, parent, store)
    @ast.ScopeConstraint::InSet(uids) => uids.contains(uid)
    @ast.ScopeConstraint::Is(ty) => uid.type_ == ty.0
    @ast.ScopeConstraint::IsIn(ty, parent) =>
      uid.type_ == ty.0 && is_descendant(uid, parent, store)
  }
}

///|
/// Check if `uid` is equal to or a descendant of `ancestor` in the entity hierarchy.
/// Uses BFS to traverse parent chains.
pub fn[S : EntityStore] is_descendant(
  uid : @ast.EntityUID,
  ancestor : @ast.EntityUID,
  store : S,
) -> Bool {
  if uid == ancestor {
    return true
  }
  let queue : Array[@ast.EntityUID] = [uid]
  let visited : Array[@ast.EntityUID] = []
  let mut pos = 0
  for ; pos < queue.length(); {
    let current = queue[pos]
    pos = pos + 1

    // Skip if already visited
    if visited.contains(current) {
      continue
    }
    visited.push(current)

    match store.get_entity(current) {
      Some(entity) =>
        for parent in entity.parents {
          if parent == ancestor {
            return true
          }
          queue.push(parent)
        }
      None => continue
    }
  }
  false
}
