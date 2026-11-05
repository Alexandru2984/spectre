import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/result
import gleeunit/should
import spectre_link/hub
import spectre_link/json_utils
import spectre_link/rate_limit
import spectre_link/validation

pub fn unicode_and_escaping_round_trip_test() {
  let text = "Salutări 👻 \"quote\" \\ slash\nline\tend"
  let body =
    json.object([#("content", json.string(text)), #("ttl", json.int(30_000))])
    |> json.to_string()
  validation.parse_message(body)
  |> should.equal(Ok(validation.NewMessage(text, 30_000, "lobby", "thought")))
  json_utils.str(text) |> json.parse(decode.string) |> should.equal(Ok(text))
}

pub fn malformed_json_and_types_rejected_test() {
  [
    "not json",
    "{\"content\":\"ok\",\"ttl\":3000} garbage",
    "{\"content\":\"ok\",\"ttl\":3.5}",
    "{\"content\":23,\"ttl\":3000}",
    "[\"content\",\"ttl\"]",
    "{\"content\":\"ok\",\"ttl\":null}",
  ]
  |> each_invalid()
}

fn each_invalid(bodies: List(String)) {
  case bodies {
    [] -> Nil
    [body, ..rest] -> {
      validation.parse_message(body) |> result.is_error() |> should.be_true()
      each_invalid(rest)
    }
  }
}

pub fn bounds_and_control_characters_test() {
  [
    "{\"content\":\" \n\",\"ttl\":3000}",
    "{\"content\":\"hello\",\"ttl\":-1}",
    "{\"content\":\"hello\",\"ttl\":300001}",
    "{\"content\":\"a\\u0000b\",\"ttl\":3000}",
  ]
  |> each_invalid()
}

pub fn independent_registry_expiry_test() {
  let assert Ok(registry) = hub.start()
  let #(code, _) =
    hub.api(
      registry,
      "POST",
      ["api", "messages"],
      "lobby",
      "",
      "",
      "",
      "unit",
      "-1",
      "",
      "{\"content\":\"temporary\",\"ttl\":3000}",
    )
  code |> should.equal(201)
  process.sleep(3150)
  retained_messages(registry) |> should.equal(0)
}

@external(erlang, "spectre_link_test_ffi", "retained_messages")
fn retained_messages(pid: process.Pid) -> Int

pub fn independent_read_write_budgets_test() {
  let assert Ok(limiter) = rate_limit.start()
  spend_writes(limiter, 30)
  process.call(limiter, 1000, fn(reply) {
    rate_limit.Check("client", rate_limit.Write, reply)
  })
  |> should.not_equal(0)
  process.call(limiter, 1000, fn(reply) {
    rate_limit.Check("client", rate_limit.Read, reply)
  })
  |> should.equal(0)
}

fn spend_writes(limiter: process.Subject(rate_limit.Msg), remaining: Int) {
  case remaining {
    0 -> Nil
    _ -> {
      process.call(limiter, 1000, fn(reply) {
        rate_limit.Check("client", rate_limit.Write, reply)
      })
      |> should.equal(0)
      spend_writes(limiter, remaining - 1)
    }
  }
}

pub fn event_expiry_removes_every_dependant_test() {
  expired_event_cleanup() |> should.equal(Nil)
}

@external(erlang, "spectre_link_test_ffi", "expired_event_cleanup")
fn expired_event_cleanup() -> Nil

pub fn replies_never_outlive_their_parent_test() {
  reply_deadlines() |> should.equal(Nil)
}

@external(erlang, "spectre_link_test_ffi", "reply_deadlines")
fn reply_deadlines() -> Nil

pub fn otp_diagnostics_redact_content_and_capabilities_test() {
  diagnostic_redaction() |> should.equal(Nil)
}

@external(erlang, "spectre_link_test_ffi", "diagnostic_redaction")
fn diagnostic_redaction() -> Nil
