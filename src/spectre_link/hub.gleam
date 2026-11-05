import gleam/erlang/process.{type Pid}

@external(erlang, "spectre_link_hub", "start_link")
pub fn start() -> Result(Pid, Nil)

@external(erlang, "spectre_link_hub", "request")
pub fn api(
  hub: Pid,
  method: String,
  path: List(String),
  room: String,
  access: String,
  moderator: String,
  client: String,
  address: String,
  since: String,
  burn: String,
  body: String,
) -> #(Int, String)
