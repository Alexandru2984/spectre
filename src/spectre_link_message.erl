%% Each message has an OTP lifetime actor; the coordinator owns its content.
-module(spectre_link_message).
-behaviour(gen_server).
-export([start_link/3,
         stop/1,
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2]).
start_link(Hub, Id, Deadline) ->
    gen_server:start_link(spectre_link_message, {Hub, Id, Deadline}, []).
stop(Pid) ->
    gen_server:cast(Pid, stop).
init({Hub, Id, Deadline}) ->
    erlang:send_after(max(0, Deadline - erlang:monotonic_time(millisecond)), self(), expire),
    {ok, {Hub, Id}}.
handle_call(_, _, State) ->
    {reply, ok, State}.
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_, State) ->
    {noreply, State}.
handle_info(expire, {Hub, Id} = State) ->
    Hub ! {expire, Id},
    {stop, normal, State};
handle_info(_, State) ->
    {noreply, State}.
