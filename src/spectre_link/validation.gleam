import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

pub type NewMessage {
  NewMessage(content: String, ttl: Int)
}

pub fn parse_message(body: String) -> Result(NewMessage, String) {
  let decoder = {
    use content <- decode.field("content", decode.string)
    use ttl <- decode.field("ttl", decode.int)
    decode.success(NewMessage(content: string.trim(content), ttl:))
  }
  use message <- result.try(
    json.parse(body, decoder)
    |> result.replace_error(
      "Expected a JSON object with content (string) and ttl (integer).",
    ),
  )
  let chars = string.length(message.content)
  let bytes = string.byte_size(message.content)
  case message {
    NewMessage(content, _) if content == "" -> Error("Write a message first.")
    _ if chars > 500 -> Error("Messages can contain up to 500 characters.")
    _ if bytes > 2000 -> Error("Message exceeds the 2000-byte UTF-8 limit.")
    NewMessage(_, ttl) if ttl < 3000 || ttl > 300_000 ->
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
