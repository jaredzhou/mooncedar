// Cedar policy AST — policy nodes and builder methods.
// References:
//   Rust: cedar-policy-core/src/ast/ (Policy, TemplateBody)
//   Go:   cedar-go/x/exp/ast/ (policy.go, scope.go)

// ---------------------------------------------------------------------------
// Scope Constraints
// ---------------------------------------------------------------------------

///|
/// Scope constraint for principal, action, or resource in a policy.
///
/// Not every variant is valid for every PARC position:
///   - Principal:  All | Eq | In | Is | IsIn
///   - Action:     All | Eq | In | InSet
///   - Resource:   All | Eq | In | Is | IsIn
pub(all) enum ScopeConstraint {
  All
  Eq(EntityUID)
  In(EntityUID)
  InSet(Array[EntityUID]) // valid for action scope
  Is(EntityType) // valid for principal & resource scope
  IsIn(EntityType, EntityUID) // valid for principal & resource scope
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Conditions & Annotations
// ---------------------------------------------------------------------------

///|
pub(all) enum ConditionKind {
  When
  Unless
} derive(Debug, Eq)

///|
pub(all) struct Condition {
  kind : ConditionKind
  body : Expr
} derive(Debug, Eq)

///|
/// Annotation — key-value metadata attached to a policy.
/// Has no effect on policy evaluation.
pub(all) struct Annotation {
  key : String
  value : String
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Policy
// ---------------------------------------------------------------------------

///|
/// A complete Cedar policy.
pub(all) struct Policy {
  id : String
  effect : PolicyEffect
  annotations : Array[Annotation]
  principal : ScopeConstraint
  action : ScopeConstraint
  resource : ScopeConstraint
  conditions : Array[Condition]
} derive(Debug, Eq)

///|
pub(all) enum PolicyEffect {
  Permit
  Forbid
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Policy builder
// ---------------------------------------------------------------------------

///|
/// Construct an EntityUID in builder contexts.
pub fn entity_uid(type_ : String, id : String) -> EntityUID {
  { type_, id }
}

///|
/// Construct an EntityType newtype in builder contexts.
pub fn entity_type(name : String) -> EntityType {
  EntityType(name)
}

///|
/// Return a zero-valued Policy with Permit effect, All scopes, empty arrays.
pub fn default() -> Policy {
  {
    id: "",
    effect: Permit,
    annotations: [],
    principal: All,
    action: All,
    resource: All,
    conditions: [],
  }
}

// ---------------------------------------------------------------------------
// Effect
// ---------------------------------------------------------------------------

///|
pub fn Policy::permit(self : Policy) -> Policy {
  Policy::{ ..self, effect: Permit }
}

///|
pub fn Policy::forbid(self : Policy) -> Policy {
  Policy::{ ..self, effect: Forbid }
}

// ---------------------------------------------------------------------------
// Scope — principal
// ---------------------------------------------------------------------------

///|
pub fn Policy::principal_eq(
  self : Policy,
  type_ : String,
  id : String,
) -> Policy {
  Policy::{ ..self, principal: Eq(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::principal_in(
  self : Policy,
  type_ : String,
  id : String,
) -> Policy {
  Policy::{ ..self, principal: In(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::principal_is(self : Policy, type_ : String) -> Policy {
  Policy::{ ..self, principal: Is(EntityType(type_)) }
}

///|
pub fn Policy::principal_is_in(
  self : Policy,
  ty : String,
  parent_ty : String,
  parent_id : String,
) -> Policy {
  Policy::{
    ..self,
    principal: IsIn(EntityType(ty), EntityUID::{
      type_: parent_ty,
      id: parent_id,
    }),
  }
}

// ---------------------------------------------------------------------------
// Scope — action
// ---------------------------------------------------------------------------

///|
pub fn Policy::action_eq(self : Policy, type_ : String, id : String) -> Policy {
  Policy::{ ..self, action: Eq(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::action_in(self : Policy, type_ : String, id : String) -> Policy {
  Policy::{ ..self, action: In(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::action_in_set(
  self : Policy,
  entities : Array[(String, String)],
) -> Policy {
  Policy::{
    ..self,
    action: InSet(
      entities.map(fn(e : (String, String)) -> EntityUID {
        let (t, i) = e
        EntityUID::{ type_: t, id: i }
      }),
    ),
  }
}

// ---------------------------------------------------------------------------
// Scope — resource
// ---------------------------------------------------------------------------

///|
pub fn Policy::resource_eq(
  self : Policy,
  type_ : String,
  id : String,
) -> Policy {
  Policy::{ ..self, resource: Eq(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::resource_in(
  self : Policy,
  type_ : String,
  id : String,
) -> Policy {
  Policy::{ ..self, resource: In(EntityUID::{ type_, id }) }
}

///|
pub fn Policy::resource_is(self : Policy, type_ : String) -> Policy {
  Policy::{ ..self, resource: Is(EntityType(type_)) }
}

///|
pub fn Policy::resource_is_in(
  self : Policy,
  ty : String,
  parent_ty : String,
  parent_id : String,
) -> Policy {
  Policy::{
    ..self,
    resource: IsIn(EntityType(ty), EntityUID::{
      type_: parent_ty,
      id: parent_id,
    }),
  }
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

///|
pub fn Policy::with_id(self : Policy, id : String) -> Policy {
  Policy::{ ..self, id, }
}

///|
pub fn Policy::annotate(self : Policy, key : String, value : String) -> Policy {
  Policy::{
    ..self,
    annotations: self.annotations + [Annotation::{ key, value }],
  }
}

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

///|
pub fn Policy::when_(self : Policy, body : Expr) -> Policy {
  Policy::{
    ..self,
    conditions: self.conditions + [Condition::{ kind: When, body }],
  }
}

///|
pub fn Policy::unless(self : Policy, body : Expr) -> Policy {
  Policy::{
    ..self,
    conditions: self.conditions + [Condition::{ kind: Unless, body }],
  }
}
