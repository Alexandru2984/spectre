import gleam/erlang/process
import gleam/int
import gleam/io
import spectre_link/config
import spectre_link/hub
import spectre_link/rate_limit
import spectre_link/web_server

pub fn main() {
  let port = config.port()
  let assert Ok(registry) = hub.start()
  let assert Ok(limiter) = rate_limit.start()
  // Linked critical actors fail with the application; systemd restarts a fresh
  // in-memory instance. Never silently move to another port or enable RPC.
  let assert Ok(_) = web_server.start(port, registry, limiter)
  io.println("Spectre-Link listening on loopback port " <> int.to_string(port))
  process.sleep_forever()
}
