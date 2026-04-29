import gleam/erlang/process
import gleam/int
import gleam/io
import spectre_link/mesh_discovery
import spectre_link/node_registry
import spectre_link/port_scanner
import spectre_link/web_server

pub fn main() {
  let port = port_scanner.find_free_port(4000)
  io.println("🔮 Spectre-Link starting on port " <> int.to_string(port))

  let assert Ok(registry) = node_registry.start()
  io.println("✅ Node registry started")

  let node_name = "spectre_link_" <> int.to_string(port) <> "@localhost"
  mesh_discovery.start(node_name)
  io.println("🌐 Distributed node: " <> node_name)

  let peer_port = case port == 4000 {
    True -> 4001
    False -> 4000
  }
  let peer = "spectre_link_" <> int.to_string(peer_port) <> "@localhost"
  case mesh_discovery.try_connect(peer) {
    mesh_discovery.Connected ->
      io.println("🔗 Connected to peer: " <> peer)
    mesh_discovery.Unreachable ->
      io.println("👻 No peer at " <> peer <> " (solo mode)")
  }

  case web_server.start(port, registry) {
    Ok(_) ->
      io.println(
        "🚀 Dashboard at http://localhost:" <> int.to_string(port),
      )
    Error(e) -> io.println("❌ Web server error: " <> e)
  }

  process.sleep_forever()
}
