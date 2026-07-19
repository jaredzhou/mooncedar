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

