import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import spectre_link/message_actor.{type MessageInfo, type Msg as ActorMsg}

pub type RegistryMsg {
  AddMessage(
    id: String,
    content: String,
    from_node: String,
    ttl_ms: Int,
    reply_to: Subject(Result(String, String)),
  )
  ListMessages(reply_to: Subject(List(MessageInfo)))
  CountMessages(reply_to: Subject(Int))
}

type Entry {
  Entry(subject: Subject(ActorMsg), info: MessageInfo)
}

type State {
  State(messages: Dict(String, Entry))
}

pub fn start() -> Result(Subject(RegistryMsg), actor.StartError) {
  actor.new(State(dict.new()))
  |> actor.on_message(handle_msg)
  |> actor.start()
  |> result_map_data()
}

fn result_map_data(
  r: Result(actor.Started(Subject(RegistryMsg)), actor.StartError),
) -> Result(Subject(RegistryMsg), actor.StartError) {
  case r {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn is_alive(subject: Subject(ActorMsg)) -> Bool {
  case process.subject_owner(subject) {
    Ok(pid) -> process.is_alive(pid)
    Error(Nil) -> False
  }
}

fn handle_msg(state: State, msg: RegistryMsg) -> actor.Next(State, RegistryMsg) {
  case msg {
    AddMessage(id, content, from_node, ttl_ms, reply_to) -> {
      let live_count =
        state.messages
        |> dict.values()
        |> list.filter(fn(e) { is_alive(e.subject) })
        |> list.length()
      case live_count >= 500 {
        True -> {
          process.send(reply_to, Error("Server at capacity (max 500 messages)"))
          actor.continue(state)
        }
        False -> {
          // Clamp TTL: min 1s, max 5min
          let safe_ttl = int.max(1000, int.min(ttl_ms, 300_000))
          let info =
            message_actor.MessageInfo(
              id: id,
              content: content,
              from_node: from_node,
              ttl_ms: safe_ttl,
              created_at: now_ms(),
            )
          case message_actor.start(info) {
            Ok(subject) -> {
              let _ =
                process.send_after(subject, safe_ttl, message_actor.Expire)
              let entry = Entry(subject: subject, info: info)
              let new_state =
                State(messages: dict.insert(state.messages, id, entry))
              process.send(reply_to, Ok(id))
              actor.continue(new_state)
            }
            Error(_) -> {
              process.send(reply_to, Error("Failed to start actor"))
              actor.continue(state)
            }
          }
        }
      }
    }

    ListMessages(reply_to) -> {
      let live =
        state.messages
        |> dict.values()
        |> list.filter(fn(e) { is_alive(e.subject) })
        |> list.map(fn(e) { e.info })
      let clean =
        state.messages
        |> dict.filter(fn(_, e) { is_alive(e.subject) })
      process.send(reply_to, live)
      actor.continue(State(messages: clean))
    }

    CountMessages(reply_to) -> {
      let count =
        state.messages
        |> dict.values()
        |> list.filter(fn(e) { is_alive(e.subject) })
        |> list.length()
      process.send(reply_to, count)
      actor.continue(state)
    }
  }
}

@external(erlang, "spectre_link_ffi", "now_ms")
fn now_ms() -> Int
