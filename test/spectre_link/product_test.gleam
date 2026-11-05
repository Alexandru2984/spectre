import gleam/result
import gleeunit/should
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
