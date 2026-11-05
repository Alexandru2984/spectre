-module(spectre_link_ffi).
-export([env/2, now_ms/0, monotonic_ms/0, random_id/0, hash/1,
         has_unsafe_controls/1, memory_mb/0]).

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
