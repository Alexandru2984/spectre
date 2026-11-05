import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub fn str(s: String) -> String {
  json.string(s) |> json.to_string()
}

pub fn num(n: Int) -> String {
  int.to_string(n)
}

pub fn obj(pairs: List(#(String, String))) -> String {
  "{"
  <> string.join(list.map(pairs, fn(p) { str(p.0) <> ":" <> p.1 }), ",")
  <> "}"
}

pub fn arr(items: List(String)) -> String {
  "[" <> string.join(items, ",") <> "]"
}
