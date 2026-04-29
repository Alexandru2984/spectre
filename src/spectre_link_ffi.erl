-module(spectre_link_ffi).
-export([find_free_port/1, start_distributed/1, ping_node/1,
         connected_nodes/0, node_name/0, memory_mb/0, now_ms/0,
         parse_message_json/1]).

find_free_port(Port) ->
    case gen_tcp:listen(Port, [{reuseaddr, true}]) of
        {ok, Socket} ->
            gen_tcp:close(Socket),
            Port;
        {error, _} ->
            find_free_port(Port + 1)
    end.

start_distributed(NodeName) when is_atom(NodeName) ->
    case net_kernel:start([NodeName, shortnames]) of
        {ok, _Pid} -> {ok, node()};
        {error, {already_started, _Pid}} -> {ok, node()};
        {error, Reason} -> {error, Reason}
    end.

ping_node(PeerNode) when is_atom(PeerNode) ->
    net_adm:ping(PeerNode).

connected_nodes() ->
    nodes().

node_name() ->
    node().

memory_mb() ->
    erlang:memory(total) div (1024 * 1024).

now_ms() ->
    erlang:system_time(millisecond).

%% Parse {"content":"...","ttl":N} — returns {ok, {Content, Ttl}} | {error, invalid}
parse_message_json(Json) when is_binary(Json) ->
    try
        {match, [_, ContentRange]} =
            re:run(Json, <<"\"content\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"">>,
                   [{capture, all}, ungreedy]),
        {match, [_, TtlRange]} =
            re:run(Json, <<"\"ttl\"\\s*:\\s*(-?\\d+)">>, [{capture, all}]),
        {CS, CL} = ContentRange,
        {TS, TL} = TtlRange,
        RawContent = binary:part(Json, CS, CL),
        TtlBin = binary:part(Json, TS, TL),
        Content = unescape_json_string(binary_to_list(RawContent)),
        Ttl = binary_to_integer(TtlBin),
        {ok, {Content, Ttl}}
    catch
        _:_ -> {error, invalid}
    end;
parse_message_json(Json) when is_list(Json) ->
    parse_message_json(list_to_binary(Json)).

unescape_json_string([]) -> [];
unescape_json_string([$\\, $" | Rest])  -> [$"  | unescape_json_string(Rest)];
unescape_json_string([$\\, $\\ | Rest]) -> [$\\ | unescape_json_string(Rest)];
unescape_json_string([$\\, $n | Rest])  -> [$\n | unescape_json_string(Rest)];
unescape_json_string([$\\, $r | Rest])  -> [$\r | unescape_json_string(Rest)];
unescape_json_string([$\\, $t | Rest])  -> [$\t | unescape_json_string(Rest)];
unescape_json_string([C | Rest])        -> [C   | unescape_json_string(Rest)].
