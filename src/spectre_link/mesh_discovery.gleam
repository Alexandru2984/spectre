import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}

pub type NodeResult {
  Connected
  Unreachable
}

@external(erlang, "spectre_link_ffi", "start_distributed")
fn do_start_distributed(node_name: Atom) -> Result(Atom, Dynamic)

@external(erlang, "spectre_link_ffi", "ping_node")
fn ping_node(peer: Atom) -> Atom

@external(erlang, "spectre_link_ffi", "connected_nodes")
pub fn connected_nodes() -> List(Atom)

@external(erlang, "spectre_link_ffi", "node_name")
pub fn node_name() -> Atom

pub fn try_connect(peer_name: String) -> NodeResult {
  let peer_atom = atom.create(peer_name)
  let result_atom = ping_node(peer_atom)
  case atom.to_string(result_atom) {
    "pong" -> Connected
    _ -> Unreachable
  }
}

pub fn start(node_name_str: String) -> Nil {
  let name_atom = atom.create(node_name_str)
  let _ = do_start_distributed(name_atom)
  Nil
}
