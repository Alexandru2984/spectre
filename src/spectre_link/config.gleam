import gleam/int
import gleam/result

@external(erlang, "spectre_link_ffi", "env")
pub fn env(name: String, fallback: String) -> String

pub fn port() -> Int {
  let value = env("PORT", "4000") |> int.parse() |> result.unwrap(0)
  assert value >= 1024 && value <= 65_535
    as "PORT must be between 1024 and 65535"
  value
}

pub fn origin() -> String {
  env("SPECTRE_ORIGIN", "https://spectre.micutu.com")
}
