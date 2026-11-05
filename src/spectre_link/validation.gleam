import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

pub type NewMessage {
  NewMessage(content: String, ttl: Int, room: String, kind: String)
}

pub fn parse_message(body: String) -> Result(NewMessage, String) {
  let decoder = {
    use content <- decode.field("content", decode.string)
    use ttl <- decode.field("ttl", decode.int)
    use room <- decode.optional_field("room", "lobby", decode.string)
    use kind <- decode.optional_field("kind", "thought", decode.string)
    decode.success(NewMessage(content: string.trim(content), ttl:, room:, kind:))
  }
  use message <- result.try(
    json.parse(body, decoder)
    |> result.replace_error(
      "Expected a JSON object with content (string) and ttl (integer).",
    ),
  )
  use _ <- result.try(validate_room(message.room))
  use _ <- result.try(validate_kind(message.kind))
  let chars = string.length(message.content)
  let bytes = string.byte_size(message.content)
  case message {
    NewMessage(content, _, _, _) if content == "" ->
      Error("Write a message first.")
    _ if chars > 500 -> Error("Messages can contain up to 500 characters.")
    _ if bytes > 2000 -> Error("Message exceeds the 2000-byte UTF-8 limit.")
    NewMessage(_, ttl, _, _) if ttl < 3000 || ttl > 300_000 ->
      Error("Lifetime must be between 3 and 300 seconds.")
    _ ->
      case has_unsafe_controls(message.content) {
        True -> Error("Message contains unsupported control characters.")
        False -> Ok(message)
      }
  }
}

@external(erlang, "spectre_link_ffi", "has_unsafe_controls")
fn has_unsafe_controls(content: String) -> Bool

pub fn validate_room(room: String) -> Result(String, String) {
  case valid_room_name(room) {
    True -> Ok(room)
    False ->
      Error(
        "Room names use 1–32 lowercase letters, numbers or hyphens, starting with a letter or number.",
      )
  }
}

fn validate_kind(kind: String) -> Result(String, String) {
  case kind {
    "thought" | "idea" | "question" -> Ok(kind)
    _ -> Error("Choose thought, idea or question.")
  }
}

pub fn parse_reaction(body: String) -> Result(String, String) {
  let decoder = {
    use emoji <- decode.field("emoji", decode.string)
    decode.success(emoji)
  }
  use emoji <- result.try(
    json.parse(body, decoder)
    |> result.replace_error("Expected an emoji field."),
  )
  case emoji {
    "spark" | "heart" | "curious" -> Ok(emoji)
    _ -> Error("Unknown reaction.")
  }
}

@external(erlang, "spectre_link_ffi", "valid_room_name")
fn valid_room_name(room: String) -> Bool

@external(erlang, "spectre_link_ffi", "valid_token")
pub fn valid_token(token: String) -> Bool
