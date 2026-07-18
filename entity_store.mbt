// Entity JSON parsing helpers + MapEntityStore — bridge @ast (Entity, Value) and @json (Json).
//
// Format: [ { uid: {...}, attrs: {...}, tags: {...}, parents: [...] }, ... ]
// References:
//   Rust: cedar-policy-core/src/entities.rs
//   Go:   cedar-go/internal/entities/

// ---------------------------------------------------------------------------
// MapEntityStore — in-memory entity store backed by a Map
// ---------------------------------------------------------------------------

///|
/// In-memory entity store backed by a Map.
pub(all) struct MapEntityStore {
  entities : Map[@ast.EntityUID, @ast.Entity]
} derive(Debug, Eq)

///|
/// MapEntityStore implements EntityStore.
pub impl @evaluator.EntityStore for MapEntityStore with fn get_entity(
  self : MapEntityStore,
  uid : @ast.EntityUID,
) -> @ast.Entity? {
  self.entities.get(uid)
}

///|
/// JSON serialization as a plain array of entities. Each entity is self-describing
/// (includes its uid), so the array format naturally captures the key-value mapping.
/// Format: [ { uid: {...}, attrs: {...}, tags: {...}, parents: [...] }, ... ]
pub impl ToJson for MapEntityStore with fn to_json(self) -> Json {
  let arr : Array[Json] = []
  for _, entity in self.entities {
    arr.push(entity.to_json())
  }
  Json::array(arr)
}

///|
/// JSON deserialization from a Cedar entity JSON array.
/// Format: [{"uid":{"type":"User","id":"alice"},"attrs":{"dept":"Eng","level":5},"tags":{},"parents":[...]}, ...]
pub impl FromJson for MapEntityStore with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> MapEntityStore raise @json.JsonDecodeError {
  match json {
    Json::Array(entries) => {
      let entities : Map[@ast.EntityUID, @ast.Entity] = Map([])
      for i = 0; i < entries.length(); i = i + 1 {
        let entry_path = path.add_index(i)
        let entity = cedar_entity_from_json(entries[i], entry_path)
        entities.set(entity.uid, entity)
      }
      MapEntityStore::{ entities, }
    }
    _ => {
      let payload : (@json.JsonPath, String) = (
        path, "expected JSON array of entities",
      )
      raise @json.JsonDecodeError(payload)
    }
  }
}

///|
/// Create an empty MapEntityStore.
pub fn new_map_store() -> MapEntityStore {
  MapEntityStore::{ entities: Map([]) }
}

// ---------------------------------------------------------------------------
// Cedar entity JSON parsing helpers
// ---------------------------------------------------------------------------

///|
/// Parse a single Cedar entity from JSON. Handles the Cedar entity JSON format:
/// { "uid": {"type":"...","id":"..."}, "attrs":{...}, "tags":{...}, "parents":[...] }
pub fn cedar_entity_from_json(
  json : Json,
  path : @json.JsonPath,
) -> @ast.Entity raise @json.JsonDecodeError {
  match json {
    Json::Object(obj) => {
      let uid = match obj.get("uid") {
        Some(uid_json) =>
          @ast.EntityUID::from_json(uid_json, path.add_key("uid"))
        None => raise @json.JsonDecodeError((path, "missing 'uid' in entity"))
      }
      let attrs = match obj.get("attrs") {
        Some(Json::Object(m)) => {
          let attrs : Map[String, @ast.Value] = Map([])
          for key, val in m {
            attrs.set(
              key,
              cedar_value_from_json(val, path.add_key("attrs").add_key(key)),
            )
          }
          attrs
        }
        Some(Json::Null) => Map([])
        Some(_) =>
          raise @json.JsonDecodeError(
            (path.add_key("attrs"), "expected object or null"),
          )
        None => Map([])
      }
      let tags = match obj.get("tags") {
        Some(Json::Object(m)) => {
          let tags : Map[String, @ast.Value] = Map([])
          for key, val in m {
            tags.set(
              key,
              cedar_value_from_json(val, path.add_key("tags").add_key(key)),
            )
          }
          tags
        }
        Some(Json::Null) => Map([])
        Some(_) =>
          raise @json.JsonDecodeError(
            (path.add_key("tags"), "expected object or null"),
          )
        None => Map([])
      }
      let parents = match obj.get("parents") {
        Some(Json::Array(parents_arr)) => {
          let parents : Array[@ast.EntityUID] = []
          for j = 0; j < parents_arr.length(); j = j + 1 {
            parents.push(
              @ast.EntityUID::from_json(
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
      @ast.Entity::{ uid, attrs, tags, parents }
    }
    _ => raise @json.JsonDecodeError((path, "expected JSON object for entity"))
  }
}

///|
/// Parse a Cedar Value from JSON. Handles the Cedar-native entity JSON format:
/// - plain numbers -> Long, strings -> String, booleans -> Bool
/// - arrays -> Set
/// - objects -> Record, EntityUID (__entity), or Extension (__extn)
pub fn cedar_value_from_json(
  json : Json,
  path : @json.JsonPath,
) -> @ast.Value raise @json.JsonDecodeError {
  match json {
    Json::True => @ast.Value::Bool(true)
    Json::False => @ast.Value::Bool(false)
    Json::Null =>
      raise @json.JsonDecodeError((path, "null is not a valid Cedar value"))
    Json::Number(n, ..) => @ast.Value::Long(n.to_int64())
    Json::String(s) => @ast.Value::String(s)
    Json::Array(arr) => {
      let values : Array[@ast.Value] = []
      for i = 0; i < arr.length(); i = i + 1 {
        values.push(cedar_value_from_json(arr[i], path.add_index(i)))
      }
      @ast.Value::Set(values)
    }
    Json::Object(obj) => cedar_value_from_object(obj, path)
  }
}

///|
/// Parse a Cedar Value from a JSON object: Record, EntityUID (__entity), or Extension (__extn).
pub fn cedar_value_from_object(
  obj : Map[String, Json],
  path : @json.JsonPath,
) -> @ast.Value raise @json.JsonDecodeError {
  // Check for __entity marker
  match obj.get("__entity") {
    Some(entity_json) => {
      let uid = @ast.EntityUID::from_json(entity_json, path.add_key("__entity"))
      return @ast.Value::EntityUID(uid)
    }
    None => ()
  }
  // Check for __extn marker
  match obj.get("__extn") {
    Some(extn_json) =>
      match extn_json {
        Json::Object(m) =>
          match (m.get("fn"), m.get("arg")) {
            (Some(Json::String(fn_name)), Some(Json::String(arg))) =>
              return @ast.Value::Extension(
                @ast.Name::{ ns: [], name: fn_name },
                arg,
              )
            _ =>
              raise @json.JsonDecodeError(
                (path.add_key("__extn"), "expected {fn, arg} strings"),
              )
          }
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("__extn"), "expected object"),
          )
      }
    None => ()
  }
  // Plain object -> Record
  let fields : Map[String, @ast.Value] = Map([])
  for key, val in obj {
    fields.set(key, cedar_value_from_json(val, path.add_key(key)))
  }
  @ast.Value::Record(fields)
}

// ---------------------------------------------------------------------------
// RequestJSON — JSON-friendly Request DTO
// ---------------------------------------------------------------------------

///|
fn entity_type_str(ty : @ast.EntityType) -> String {
  match ty {
    @ast.EntityType(s) => s
  }
}

///|
/// Serialize an EntityUIDEntry to a Cedar text string.
fn parc_to_str(entry : @evaluator.EntityUIDEntry) -> String? {
  match entry {
    @evaluator.Concrete(uid) => Some(uid.type_ + "::\"" + uid.id + "\"")
    @evaluator.Unknown(ty) => {
      let s = entity_type_str(ty)
      if s == "" {
        None
      } else {
        Some(s)
      }
    }
  }
}

///|
/// Parse a Cedar text string → EntityUIDEntry (best-effort, never raises).
fn parc_from_str(s : String?) -> @evaluator.EntityUIDEntry {
  match s {
    None => @evaluator.Unknown(@ast.EntityType(""))
    Some(s) => {
      let mut has_colons = false
      for i = 0; i < s.length() - 1; i = i + 1 {
        if s[i] == ':' && s[i + 1] == ':' {
          has_colons = true
          break
        }
      }
      if has_colons {
        match parc_parse_euid(s) {
          Some(uid) => @evaluator.Concrete(uid)
          None => @evaluator.Unknown(@ast.EntityType(s))
        }
      } else {
        @evaluator.Unknown(@ast.EntityType(s))
      }
    }
  }
}

///|
fn parc_parse_euid(s : String) -> @ast.EntityUID? {
  let len = s.length()
  let mut sep = -1
  let mut idx = len - 3
  while idx >= 0 {
    if s[idx] == ':' && s[idx + 1] == ':' && s[idx + 2] == '"' {
      sep = idx
      break
    }
    idx = idx - 1
  }
  if sep < 0 {
    return None
  }
  let type_ = s[:sep].to_owned()
  let id_start = sep + 3
  let mut id_len = 0
  for i = id_start; i < len; i = i + 1 {
    if s[i] == '"' {
      id_len = i - id_start
      break
    }
  }
  if id_len == 0 {
    return None
  }
  let id = s[id_start:id_start + id_len].to_owned()
  Some(@ast.EntityUID::{ type_, id })
}

///|
/// JSON-friendly representation of an authorization Request.
///
/// ```json
/// {
///   "principal":"GitApp::User::\"JaneDoe\"",
///   "action":"Action::\"view\"",
///   "resource":"Photo::\"x\"",
///   "context":{"is_admin":true}
/// }
/// ```
///
/// - PARC strings: "Type::\"id\"" → Concrete, "Type" → Unknown, null/absent → Unknown("")
/// - PARC objects: {"type":"..","id":".."} → normalised to string
/// - Context absent/empty-object/null → Unknown, otherwise → Concrete
pub(all) struct RequestJSON {
  principal : String?
  action : String?
  resource : String?
  context : @ast.Value?
} derive(Debug, Eq)

///|
/// Convert a Request to its JSON-friendly representation.
pub fn to_request_json(req : @evaluator.Request) -> RequestJSON {
  RequestJSON::{
    principal: parc_to_str(req.principal),
    action: parc_to_str(req.action),
    resource: parc_to_str(req.resource),
    context: match req.context {
      @evaluator.Concrete(v) => Some(v)
      @evaluator.Unknown => None
      @evaluator.Partial(_) => None
    },
  }
}

///|
/// Convert a RequestJSON into a full Request.
pub fn RequestJSON::to_request(self : RequestJSON) -> @evaluator.Request {
  @evaluator.Request::{
    principal: parc_from_str(self.principal),
    action: parc_from_str(self.action),
    resource: parc_from_str(self.resource),
    context: match self.context {
      Some(v) => @evaluator.Concrete(v)
      None => @evaluator.Unknown
    },
  }
}

///|
pub impl ToJson for RequestJSON with fn to_json(self) -> Json {
  let fields : Map[String, Json] = Map([])
  match self.principal {
    Some(s) => fields.set("principal", Json::string(s))
    None => fields.set("principal", Json::string(""))
  }
  match self.action {
    Some(s) => fields.set("action", Json::string(s))
    None => fields.set("action", Json::string(""))
  }
  match self.resource {
    Some(s) => fields.set("resource", Json::string(s))
    None => fields.set("resource", Json::string(""))
  }
  match self.context {
    Some(v) => fields.set("context", v.to_json())
    None => fields.set("context", Json::object(Map([])))
  }
  Json::object(fields)
}

///|
/// Deserialize RequestJSON from JSON. Supports both PARC string and object formats.
pub impl FromJson for RequestJSON with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> RequestJSON raise @json.JsonDecodeError {
  match json {
    Json::Object(obj) => {
      let principal = match obj.get("principal") {
        Some(j) =>
          match j {
            Json::String(s) => Some(s)
            Json::Object(_) => {
              let uid = @ast.EntityUID::from_json(j, path.add_key("principal"))
              Some(uid.type_ + "::\"" + uid.id + "\"")
            }
            Json::Null => None
            _ =>
              raise @json.JsonDecodeError(
                (path.add_key("principal"), "expected string, object, or null"),
              )
          }
        None => None
      }
      let action = match obj.get("action") {
        Some(j) =>
          match j {
            Json::String(s) => Some(s)
            Json::Object(_) => {
              let uid = @ast.EntityUID::from_json(j, path.add_key("action"))
              Some(uid.type_ + "::\"" + uid.id + "\"")
            }
            Json::Null => None
            _ =>
              raise @json.JsonDecodeError(
                (path.add_key("action"), "expected string, object, or null"),
              )
          }
        None => None
      }
      let resource = match obj.get("resource") {
        Some(j) =>
          match j {
            Json::String(s) => Some(s)
            Json::Object(_) => {
              let uid = @ast.EntityUID::from_json(j, path.add_key("resource"))
              Some(uid.type_ + "::\"" + uid.id + "\"")
            }
            Json::Null => None
            _ =>
              raise @json.JsonDecodeError(
                (path.add_key("resource"), "expected string, object, or null"),
              )
          }
        None => None
      }
      let context = match obj.get("context") {
        Some(j) =>
          match j {
            Json::Null => None
            Json::Object(inner) =>
              if inner.length() == 0 {
                None
              } else {
                Some(cedar_value_from_json(j, path.add_key("context")))
              }
            _ => Some(cedar_value_from_json(j, path.add_key("context")))
          }
        None => None
      }
      RequestJSON::{ principal, action, resource, context }
    }
    _ => raise @json.JsonDecodeError((path, "expected object"))
  }
}
