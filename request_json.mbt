// RequestJSON — JSON-friendly Request DTO for Cedar authorization requests.
//
// References:
//   Rust: cedar-policy-core/src/entities.rs
//   Go:   cedar-go/internal/entities/

// ---------------------------------------------------------------------------
// Internal PARC string helpers
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

// ---------------------------------------------------------------------------
// RequestJSON struct
// ---------------------------------------------------------------------------

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
