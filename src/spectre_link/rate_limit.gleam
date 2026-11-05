import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/otp/actor
import gleam/result

pub type Bucket {
  Read
  Write
}

pub type Msg {
  Check(key: String, bucket: Bucket, reply: Subject(Int))
  Sweep
}

type Window {
  Window(started: Int, count: Int)
}

type State {
  State(windows: Dict(#(String, Bucket), Window), subject: Subject(Msg))
}

pub fn start() -> Result(Subject(Msg), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let _ = process.send_after(subject, 60_000, Sweep)
    Ok(
      actor.initialised(State(dict.new(), subject)) |> actor.returning(subject),
    )
  })
  |> actor.on_message(handle)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle(state: State, message: Msg) -> actor.Next(State, Msg) {
  case message {
    Sweep -> {
      let now = monotonic_ms()
      let windows =
        dict.filter(state.windows, fn(_, w) { now - w.started < 60_000 })
      let _ = process.send_after(state.subject, 60_000, Sweep)
      actor.continue(State(..state, windows:))
    }
    Check(key, bucket, reply) -> {
      let now = monotonic_ms()
      let budget = case bucket {
        Read -> 240
        Write -> 30
      }
      let global_budget = case bucket {
        Read -> 30_000
        Write -> 600
      }
      let #(windows, global_wait) =
        consume(state.windows, #("global", bucket), now, global_budget)
      let #(windows, client_wait) = case global_wait {
        0 -> consume(windows, #(key, bucket), now, budget)
        _ -> #(windows, global_wait)
      }
      process.send(reply, int.max(global_wait, client_wait))
      actor.continue(State(..state, windows:))
    }
  }
}

fn consume(
  windows: Dict(#(String, Bucket), Window),
  key: #(String, Bucket),
  now: Int,
  limit: Int,
) -> #(Dict(#(String, Bucket), Window), Int) {
  let window = case dict.get(windows, key) {
    Ok(w) if now - w.started < 60_000 -> w
    _ -> Window(now, 0)
  }
  case
    window.count >= limit
    || dict.size(windows) >= 10_000
    && !dict.has_key(windows, key)
  {
    True -> #(
      windows,
      int.max(1, { 60_000 - { now - window.started } + 999 } / 1000),
    )
    False -> #(
      dict.insert(windows, key, Window(..window, count: window.count + 1)),
      0,
    )
  }
}

@external(erlang, "spectre_link_ffi", "monotonic_ms")
fn monotonic_ms() -> Int
