%% Bounded OTP state. Room authorization and mutations are serialized.
%% Reserved managed IDs fail closed; child expiry and removal cascade.
-module(spectre_link_test_ffi).
-export([retained_messages/1,expired_event_cleanup/0, reply_deadlines/0, diagnostic_redaction/0]).
retained_messages(Pid) ->
    map_size(maps:get(messages, sys:get_state(Pid))).
expired_event_cleanup() ->
    {ok, Hub} = spectre_link_hub:start_link(),
    Client = spectre_link_ffi:random_id(),
    Call =
        fun(Method, Path, Room, Access, Mod, Data) ->
               {Code, Raw} =
                   spectre_link_hub:request(Hub, Method, Path, Room,
                                            Access, Mod, Client,
                                            <<"unit">>,
                                            <<"-1">>,
                                            <<>>,
                                            iolist_to_binary(json:encode(Data))),
               {Code, json:decode(Raw)}
        end,
    {201, Created} =
        Call(<<"POST">>,
             [<<"api">>, <<"rooms">>],
             <<"lobby">>,
             <<>>, <<>>,
             #{name => <<"Expiry test">>,
               minutes => 15,
               private => true}),
    Room = maps:get(<<"id">>, maps:get(<<"room">>, Created)),
    Access = maps:get(<<"access_key">>, Created),
    Owner = maps:get(<<"owner_key">>, Created),
    {201, Parent} =
        Call(<<"POST">>,
             [<<"api">>, <<"messages">>],
             Room, Access, <<>>,
             #{content => <<"question">>,
               ttl => 300000,
               room => Room,
               kind => <<"poll">>,
               options => [<<"one">>, <<"two">>]}),
    Id = maps:get(<<"id">>, Parent),
    {201, _} =
        Call(<<"POST">>,
             [<<"api">>, <<"messages">>],
             Room, Access, <<>>,
             #{content => <<"reply">>,
               ttl => 300000,
               room => Room,
               parent_id => Id}),
    {200, _} =
        Call(<<"POST">>,
             [<<"api">>, <<"messages">>, Id, <<"vote">>],
             Room, Access, <<>>,
             #{option => 0}),
    {200, _} =
        Call(<<"POST">>,
             [<<"api">>, <<"messages">>, Id, <<"report">>],
             Room, Access, <<>>,
             #{reason => <<"spam">>}),
    {200, _} =
        Call(<<"POST">>,
             [<<"api">>, <<"presence">>],
             Room, Access, <<>>,
             #{alias => <<"temporary">>}),
    sys:replace_state(Hub,
                      fun(S) ->
                             S#{rooms :=
                                    maps:map(fun(_, R) ->
                                                    R#{deadline :=
                                                           erlang:monotonic_time(millisecond)
                                                           -
                                                           1}
                                             end,
                                             maps:get(rooms, S))}
                      end),
    timer:sleep(650),
    S = sys:get_state(Hub),
    true =
        lists:all(fun(K) ->
                         map_size(maps:get(K, S)) =:= 0
                  end,
                  [messages, rooms, reports, sessions]),
    {404, _} =
        Call(<<"GET">>,
             [<<"api">>, <<"messages">>],
             Room, Access, Owner,
             #{}),
    nil.

reply_deadlines() ->
    {ok,Hub}=spectre_link_hub:start_link(),
    Send=fun(Data)->
        {201,Raw}=spectre_link_hub:request(Hub,<<"POST">>,[<<"api">>,<<"messages">>],<<"lobby">>,<<>>,<<>>,<<>>,<<"unit">>,<<"-1">>,<<>>,iolist_to_binary(json:encode(Data))),
        maps:get(<<"message">>,json:decode(Raw))
    end,
    Parent=Send(#{content=><<"parent">>,ttl=>3000}),Id=maps:get(<<"id">>,Parent),
    [begin
        Child=Send(#{content=><<"reply">>,ttl=>300000,parent_id=>Id}),
        true=maps:get(<<"expires_at">>,Child)=<maps:get(<<"expires_at">>,Parent)
     end || _<-lists:seq(1,20)],
    State=sys:get_state(Hub),Messages=maps:get(messages,State),D=maps:get(deadline,maps:get(Id,Messages)),
    true=lists:all(fun(M)->maps:get(deadline,M)=<D end,maps:values(Messages)),
    nil.

diagnostic_redaction() ->
    Secret= <<"fixture-content-and-capability-never-in-diagnostics">>,
    Status=spectre_link_hub:format_status(#{state=>#{content=>Secret},message=>Secret,reason=>Secret,log=>[Secret]}),
    nomatch=binary:match(term_to_binary(Status),Secret),
    nil.
