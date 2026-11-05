import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import spectre_link/message_actor.{type MessageInfo, type Msg as ActorMsg}

pub type RegistryMsg {
  AddMessage(
    id: String,
    content: String,
    room: String,
    kind: String,
    ttl_ms: Int,
    burn_hash: String,
    reply_to: Subject(Result(MessageInfo, String)),
  )
  ListMessages(room: String, reply_to: Subject(List(MessageInfo)))
  CountMessages(reply_to: Subject(Int))
  BurnMessage(
    id: String,
    room: String,
    burn_hash: String,
    reply_to: Subject(Bool),
  )
  React(
    id: String,
    room: String,
    client: String,
    emoji: String,
    reply_to: Subject(Result(MessageInfo, String)),
  )
  Sweep
  ExpireMessage(id: String)
}

type Entry {
  Entry(
    subject: Subject(ActorMsg),
    info: MessageInfo,
    deadline: Int,
    burn_hash: String,
    votes: Dict(String, String),
  )
}

type State {
  State(messages: Dict(String, Entry), subject: Subject(RegistryMsg))
}

pub fn start() -> Result(Subject(RegistryMsg), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let _ = process.send_after(subject, 1000, Sweep)
    Ok(
      actor.initialised(State(dict.new(), subject)) |> actor.returning(subject),
    )
  })
  |> actor.on_message(handle_msg)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn is_alive(subject: Subject(ActorMsg)) -> Bool {
  case process.subject_owner(subject) {
    Ok(pid) -> process.is_alive(pid)
    Error(_) -> False
  }
}

fn handle_msg(
  state: State,
  msg: RegistryMsg,
) -> actor.Next(State, RegistryMsg) {
  let now = monotonic_ms()
  let state =
    State(
      ..state,
      messages: dict.filter(state.messages, fn(_, e) {
        e.deadline > now && is_alive(e.subject)
      }),
    )
  case msg {
    Sweep -> {
      let _ = process.send_after(state.subject, 1000, Sweep)
      actor.continue(state)
    }
    ExpireMessage(id) ->
      actor.continue(State(..state, messages: dict.delete(state.messages, id)))
    CountMessages(reply) -> {
      process.send(reply, dict.size(state.messages))
      actor.continue(state)
    }
    ListMessages(room, reply) -> {
      let live =
        dict.values(state.messages)
        |> list.filter(fn(e) { e.info.room == room })
        |> list.map(fn(e) { e.info })
      process.send(reply, live)
      actor.continue(state)
    }
    AddMessage(id, content, room, kind, ttl_ms, burn_hash, reply) -> {
      let room_count =
        dict.values(state.messages) |> list.count(fn(e) { e.info.room == room })
      case dict.size(state.messages) >= 500 || room_count >= 100 {
        True -> {
          process.send(
            reply,
            Error(
              "This room or server is at capacity. Try again after messages expire.",
            ),
          )
          actor.continue(state)
        }
        False -> {
          let safe_ttl = int.max(1000, int.min(ttl_ms, 300_000))
          let info =
            message_actor.MessageInfo(
              id:,
              content:,
              room:,
              kind:,
              reactions: dict.new(),
              ttl_ms: safe_ttl,
              created_at: now_ms(),
            )
          case message_actor.start(info) {
            Ok(subject) -> {
              let _ =
                process.send_after(subject, safe_ttl, message_actor.Expire)
              let _ =
                process.send_after(state.subject, safe_ttl, ExpireMessage(id))
              let entry =
                Entry(
                  subject:,
                  info:,
                  deadline: monotonic_ms() + safe_ttl,
                  burn_hash:,
                  votes: dict.new(),
                )
              process.send(reply, Ok(info))
              actor.continue(
                State(..state, messages: dict.insert(state.messages, id, entry)),
              )
            }
            Error(_) -> {
              process.send(
                reply,
                Error("Unable to create message. Try again shortly."),
              )
              actor.continue(state)
            }
          }
        }
      }
    }
    BurnMessage(id, room, burn_hash, reply) -> {
      case dict.get(state.messages, id) {
        Ok(entry) if entry.info.room == room && entry.burn_hash == burn_hash -> {
          process.send(entry.subject, message_actor.Expire)
          process.send(reply, True)
          actor.continue(
            State(..state, messages: dict.delete(state.messages, id)),
          )
        }
        _ -> {
          process.send(reply, False)
          actor.continue(state)
        }
      }
    }
    React(id, room, client, emoji, reply) -> {
      case dict.get(state.messages, id) {
        Ok(entry) if entry.info.room == room -> {
          case
            dict.size(entry.votes) >= 256 && !dict.has_key(entry.votes, client)
          {
            True -> {
              process.send(reply, Error("Reaction capacity reached."))
              actor.continue(state)
            }
            False -> {
              let votes = case dict.get(entry.votes, client) {
                Ok(previous) if previous == emoji ->
                  dict.delete(entry.votes, client)
                _ -> dict.insert(entry.votes, client, emoji)
              }
              let counts =
                dict.values(votes)
                |> list.fold(dict.new(), fn(counts, key) {
                  dict.insert(
                    counts,
                    key,
                    { dict.get(counts, key) |> result.unwrap(0) } + 1,
                  )
                })
              let info =
                message_actor.MessageInfo(..entry.info, reactions: counts)
              let entry = Entry(..entry, votes:, info:)
              process.send(reply, Ok(info))
              actor.continue(
                State(..state, messages: dict.insert(state.messages, id, entry)),
              )
            }
          }
        }
        _ -> {
          process.send(
            reply,
            Error("Message has expired or does not exist in this room."),
          )
          actor.continue(state)
        }
      }
    }
  }
}

@external(erlang, "spectre_link_ffi", "now_ms")
fn now_ms() -> Int

@external(erlang, "spectre_link_ffi", "monotonic_ms")
fn monotonic_ms() -> Int
