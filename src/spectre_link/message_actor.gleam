import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type MessageInfo {
  MessageInfo(
    id: String,
    content: String,
    from_node: String,
    ttl_ms: Int,
    created_at: Int,
  )
}

pub type Msg {
  GetInfo(reply_to: Subject(MessageInfo))
  Expire
}

type State {
  State(info: MessageInfo)
}

pub fn start(info: MessageInfo) -> Result(Subject(Msg), actor.StartError) {
  actor.new(State(info))
  |> actor.on_message(handle_msg)
  |> actor.start()
  |> result_map_data()
}

fn result_map_data(
  r: Result(actor.Started(Subject(Msg)), actor.StartError),
) -> Result(Subject(Msg), actor.StartError) {
  case r {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn handle_msg(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    GetInfo(reply_to) -> {
      process.send(reply_to, state.info)
      actor.continue(state)
    }
    Expire -> actor.stop()
  }
}
