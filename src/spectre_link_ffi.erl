-module(spectre_link_ffi).
-export([env/2, now_ms/0, monotonic_ms/0, random_id/0, hash/1,
         has_unsafe_controls/1, valid_room_name/1, valid_token/1, memory_mb/0]).

env(Name, Fallback) ->
    case os:getenv(binary_to_list(Name)) of
        false -> Fallback;
        Value -> unicode:characters_to_binary(Value)
    end.
now_ms() -> erlang:system_time(millisecond).
monotonic_ms() -> erlang:monotonic_time(millisecond).
random_id() -> binary:encode_hex(crypto:strong_rand_bytes(24), lowercase).
hash(Value) -> binary:encode_hex(crypto:hash(sha256, Value), lowercase).
memory_mb() -> erlang:memory(total) div (1024 * 1024).
has_unsafe_controls(Content) ->
    re:run(Content, <<"[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]">>, [{capture, none}]) =:= match.

valid_room_name(Room) -> re:run(Room, <<"^[a-z0-9][a-z0-9-]{0,31}$">>, [{capture, none}]) =:= match.
valid_token(Token) -> byte_size(Token) =:= 48 andalso re:run(Token, <<"^[0-9a-f]{48}$">>, [{capture, none}]) =:= match.
