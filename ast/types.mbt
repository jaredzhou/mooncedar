// Cedar runtime types — the type system and value representations.
// References:
//   Rust: cedar-policy-core/src/ast/ (Type, ValueKind, EntityUID)
//   Go:   cedar-go/types/ (Value interface, concrete types)

// ---------------------------------------------------------------------------
// Identifiers & Names
// ---------------------------------------------------------------------------

///|
/// A unique entity identifier, e.g. `User::"alice"`.
pub(all) struct EntityUID {
  type_ : String
  id : String
} derive(Debug, Eq, Hash)

///|
/// An entity type name, e.g. `User`, `Photo`.
pub(all) struct EntityType(String) derive(Debug, Eq, ToJson, FromJson)

///|
/// A namespaced path for extension functions, e.g. `ip`, `decimal`.
pub(all) struct Name {
  ns : Array[String]
  name : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Source position for diagnostics / error messages.
pub(all) struct Position {
  filename : String // optional source file name, "" if unknown
  offset : Int // byte offset, starting at 0
  line : Int // line number, starting at 1
  column : Int // column number, starting at 1
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Pattern (for the `like` operator)
// ---------------------------------------------------------------------------

///|
/// Pattern for the `like` operator (IAM-style `StringLike`).
/// The wildcard `*` matches any string; `\*` matches a literal `*`.
pub(all) struct Pattern {
  elements : Array[PatternElem]
} derive(Debug, Eq)

///|
pub(all) enum PatternElem {
  Char(Char)
  Wildcard
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Type — the Cedar type system (Rust approach)
// ---------------------------------------------------------------------------

///|
/// The runtime type of a Cedar value.
/// Two entity types are equal iff they have the same Name.
/// Two extension types are equal iff they have the same Name.
pub(all) enum Type {
  Bool
  Long
  String
  Set
  Record
  Entity(EntityType)
  Extension(Name)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Value — all runtime values (Rust ValueKind, flattened)
// ---------------------------------------------------------------------------

///|
/// All values that can be the dynamic result of evaluating an Expr.
/// Includes extension values (ip, decimal, datetime, duration, etc.)
/// as opaque Extension(Name, String) entries for MVP.
pub(all) enum Value {
  Bool(Bool)
  Long(Int64)
  String(String)
  EntityUID(EntityUID)
  Set(Array[Value])
  Record(Map[String, Value])
  Extension(Name, String) // opaque: (fn_name, serialized_arg)
} derive(Debug, Eq, ToJson, FromJson)

// ---------------------------------------------------------------------------
// PartialValue — unified partial evaluation value
// ---------------------------------------------------------------------------

///|
/// Result of evaluating an expression — either a concrete value or a residual
/// expression that could not be reduced (partial evaluation).
///
/// Also used as the value type in Entity attrs/tags, because entity attributes
/// and tags can be unknown during partial evaluation (source #5 of Unknown).
pub(all) enum PartialValue {
  Value(Value)
  Residual(Expr)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Entity — application data for evaluation (attrs + tags + parents)
// ---------------------------------------------------------------------------

///|
/// An entity as provided by the application. Contains attributes (schema-defined),
/// tags (free-form), and parent relationships for hierarchy traversal (`in` operator).
pub(all) struct Entity {
  uid : EntityUID
  attrs : Map[String, Value]
  tags : Map[String, Value]
  parents : Array[EntityUID]
} derive(Debug, Eq)

///|
/// Serialize an Entity to JSON.
pub impl ToJson for Entity with fn to_json(self) -> Json {
  let attrs_obj : Map[String, Json] = Map([])
  for key, v in self.attrs {
    attrs_obj.set(key, v.to_json())
  }
  let tags_obj : Map[String, Json] = Map([])
  for key, v in self.tags {
    tags_obj.set(key, v.to_json())
  }
  Json::object(
    Map([
      ("uid", self.uid.to_json()),
      ("attrs", Json::object(attrs_obj)),
      ("tags", Json::object(tags_obj)),
      ("parents", Json::array(self.parents.map(fn(p) { p.to_json() }))),
    ]),
  )
}

///|
/// Deserialize an Entity from JSON.
pub impl FromJson for Entity with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Entity raise @json.JsonDecodeError {
  match json {
    Json::Object(obj) => {
      let uid = match obj.get("uid") {
        Some(uid_json) => EntityUID::from_json(uid_json, path.add_key("uid"))
        None => raise @json.JsonDecodeError((path, "missing 'uid' in entity"))
      }
      let attrs = match obj.get("attrs") {
        Some(Json::Object(m)) => {
          let attrs : Map[String, Value] = Map([])
          for key, val in m {
            attrs.set(
              key,
              Value::from_json(val, path.add_key("attrs").add_key(key)),
            )
          }
          attrs
        }
        None => Map([])
        Some(_) =>
          raise @json.JsonDecodeError(
            (path.add_key("attrs"), "expected object"),
          )
      }
      let tags = match obj.get("tags") {
        Some(Json::Object(m)) => {
          let tags : Map[String, Value] = Map([])
          for key, val in m {
            tags.set(
              key,
              Value::from_json(val, path.add_key("tags").add_key(key)),
            )
          }
          tags
        }
        None => Map([])
        Some(_) =>
          raise @json.JsonDecodeError((path.add_key("tags"), "expected object"))
      }
      let parents = match obj.get("parents") {
        Some(Json::Array(parents_arr)) => {
          let parents : Array[EntityUID] = []
          for j = 0; j < parents_arr.length(); j = j + 1 {
            parents.push(
              EntityUID::from_json(
                parents_arr[j],
                path.add_key("parents").add_index(j),
              ),
            )
          }
          parents
        }
        Some(_) =>
          raise @json.JsonDecodeError(
            (path.add_key("parents"), "expected array"),
          )
        None => []
      }
      Entity::{ uid, attrs, tags, parents }
    }
    _ => raise @json.JsonDecodeError((path, "expected JSON object for entity"))
  }
}

// (Request, Decision, Diagnostic* types moved to evaluator/request.mbt)

// ---------------------------------------------------------------------------
// EntityUID JSON: map type_ (MoonBit keyword workaround) ↔ "type" (Cedar JSON)
// ---------------------------------------------------------------------------

///|
/// Serialize EntityUID as Cedar-compatible JSON: { "type": "...", "id": "..." }.
pub impl ToJson for EntityUID with fn to_json(self) -> Json {
  Json::object(
    Map([("type", Json::string(self.type_)), ("id", Json::string(self.id))]),
  )
}

///|
/// Deserialize from Cedar JSON entity UID format.
pub impl FromJson for EntityUID with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> EntityUID raise @json.JsonDecodeError {
  match json {
    Json::Object(fields) =>
      match (fields.get("type"), fields.get("id")) {
        (Some(Json::String(type_s)), Some(Json::String(id_s))) =>
          EntityUID::{ type_: type_s, id: id_s }
        _ => {
          let payload : (@json.JsonPath, String) = (
            path, "expected {type, id} for EntityUID",
          )
          raise @json.JsonDecodeError(payload)
        }
      }
    _ => {
      let payload : (@json.JsonPath, String) = (
        path, "expected object for EntityUID",
      )
      raise @json.JsonDecodeError(payload)
    }
  }
}
