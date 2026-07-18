// Policy validator — semantic checks for Cedar policies.
// References:
//   Rust: cedar-policy-validator/
//   Cedar spec: scope constraint rules per PARC position

///|
/// Validation error with a message and the offending policy id.
pub(all) suberror ValidationError {
  ValidationError(String, String)
} derive(Debug)

///|
/// Validate a single policy's scope constraints.
///
/// | Position   | Valid variants                    | Invalid |
/// |------------|-----------------------------------|---------|
/// | Principal  | All, Eq, In, Is, IsIn             | InSet   |
/// | Action     | All, Eq, In, InSet                | Is, IsIn|
/// | Resource   | All, Eq, In, Is, IsIn             | InSet   |
pub fn validate_policy(policy : Policy) -> Unit raise ValidationError {
  // Principal: no InSet
  if policy.principal is InSet(_) {
    raise ValidationError(
      "principal scope cannot use 'in [...]' (InSet)",
      policy.id,
    )
  }

  // Action: no Is or IsIn
  if policy.action is Is(_) {
    raise ValidationError("action scope cannot use 'is'", policy.id)
  }
  if policy.action is IsIn(_, _) {
    raise ValidationError("action scope cannot use 'is ... in'", policy.id)
  }

  // Resource: no InSet
  if policy.resource is InSet(_) {
    raise ValidationError(
      "resource scope cannot use 'in [...]' (InSet)",
      policy.id,
    )
  }
}

///|
/// Validate all policies in a policy set. Raises on the first invalid policy found.
pub fn validate_policies(
  policies : Array[Policy],
) -> Unit raise ValidationError {
  for policy in policies {
    validate_policy(policy)
  }
}
