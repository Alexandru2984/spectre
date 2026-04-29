import gleam/int
import gleam/list
import gleam/string

/// Encode a string as a JSON string literal with basic escaping.
pub fn str(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")
    |> string.replace("\t", "\\t")
  "\"" <> escaped <> "\""
}

/// Encode an integer as a JSON number.
pub fn num(n: Int) -> String {
  int.to_string(n)
}

/// Build a JSON object from key/value string pairs.
pub fn obj(pairs: List(#(String, String))) -> String {
  let fields = list.map(pairs, fn(p) { str(p.0) <> ":" <> p.1 })
  "{" <> string.join(fields, ",") <> "}"
}

/// Build a JSON array from pre-encoded string values.
pub fn arr(items: List(String)) -> String {
  "[" <> string.join(items, ",") <> "]"
}
