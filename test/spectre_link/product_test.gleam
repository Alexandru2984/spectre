import gleam/dict
import gleam/erlang/process
import gleam/result
import gleeunit/should
import spectre_link/node_registry
import spectre_link/validation

pub fn room_and_kind_validation_test() {
  validation.validate_room("my-room-2") |> should.equal(Ok("my-room-2"))
  validation.validate_room("../secret") |> result.is_error() |> should.be_true()
  validation.validate_room("lobby\n") |> result.is_error() |> should.be_true()
  validation.validate_room("UPPERCASE") |> result.is_error() |> should.be_true()
  validation.parse_message(
    "{\"content\":\"hey\",\"ttl\":3000,\"kind\":\"script\"}",
  )
  |> result.is_error()
  |> should.be_true()
  validation.parse_message("{\"content\":\"hey\",\"ttl\":3000,\"room\":null}")
  |> result.is_error()
  |> should.be_true()
  validation.parse_reaction("{\"emoji\":\"spark\"}")
  |> should.equal(Ok("spark"))
  validation.parse_reaction("{\"emoji\":\"anything\"}")
  |> result.is_error()
  |> should.be_true()
}

pub fn room_isolation_reactions_and_burn_test() {
  let assert Ok(registry) = node_registry.start()
  let assert Ok(_) =
    process.call(registry, 1000, fn(reply) {
      node_registry.AddMessage(
        "product-test",
        "hello",
        "room-a",
        "idea",
        30_000,
        "secret-hash",
        reply,
      )
    })
  process.call(registry, 1000, fn(reply) {
    node_registry.ListMessages("room-b", reply)
  })
  |> should.equal([])
  process.call(registry, 1000, fn(reply) {
    node_registry.React("product-test", "room-b", "client", "spark", reply)
  })
  |> result.is_error()
  |> should.be_true()
  let assert Ok(first) =
    process.call(registry, 1000, fn(reply) {
      node_registry.React("product-test", "room-a", "client", "spark", reply)
    })
  dict.get(first.reactions, "spark") |> should.equal(Ok(1))
  let assert Ok(second) =
    process.call(registry, 1000, fn(reply) {
      node_registry.React("product-test", "room-a", "client", "heart", reply)
    })
  dict.get(second.reactions, "spark") |> should.equal(Error(Nil))
  dict.get(second.reactions, "heart") |> should.equal(Ok(1))
  let assert Ok(third) =
    process.call(registry, 1000, fn(reply) {
      node_registry.React("product-test", "room-a", "client", "heart", reply)
    })
  dict.size(third.reactions) |> should.equal(0)
  process.call(registry, 1000, fn(reply) {
    node_registry.BurnMessage("product-test", "room-b", "secret-hash", reply)
  })
  |> should.be_false()
  process.call(registry, 1000, fn(reply) {
    node_registry.BurnMessage("product-test", "room-a", "wrong-hash", reply)
  })
  |> should.be_false()
  process.call(registry, 1000, fn(reply) {
    node_registry.BurnMessage("product-test", "room-a", "secret-hash", reply)
  })
  |> should.be_true()
  process.call(registry, 1000, fn(reply) {
    node_registry.ListMessages("room-a", reply)
  })
  |> should.equal([])
}
