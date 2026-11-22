-module(spectre_link_session_test_ffi).
-export([session_authorization/0, spotlight_expiry/0]).

call(Hub, Method, Path, Room, Access, Mod, Burn, Data) ->
    {Code, Raw} = spectre_link_hub:request(Hub, Method, Path, Room, Access, Mod,
        binary:copy(<<"d">>, 48), <<"session-unit">>, <<"-1">>, Burn,
        iolist_to_binary(json:encode(Data))),
    {Code, json:decode(Raw)}.

event(Hub, Name) ->
    {201, Created} = call(Hub, <<"POST">>, [<<"api">>, <<"rooms">>], <<"lobby">>, <<>>, <<>>, <<>>,
                          #{name => Name, private => true}),
    {maps:get(<<"id">>, maps:get(<<"room">>, Created)), maps:get(<<"access_key">>, Created),
     maps:get(<<"owner_key">>, Created)}.

send(Hub, Room, Access, Kind, Parent, TTL) ->
    Options = case Kind of <<"poll">> -> [<<"One">>, <<"Two">>]; _ -> [] end,
    {201, M} = call(Hub, <<"POST">>, [<<"api">>, <<"messages">>], Room, Access, <<>>, <<>>,
                    #{room => Room, content => <<"Temporary fixture">>, kind => Kind,
                      parent_id => Parent, ttl => TTL, options => Options}),
    {maps:get(<<"id">>, M), maps:get(<<"burn_key">>, M), maps:get(<<"message">>, M)}.

session_authorization() ->
    {ok, Hub} = spectre_link_hub:start_link(),
    {Room, Access, Owner} = event(Hub, <<"Session tools">>),
    {Other, OtherAccess, OtherOwner} = event(Hub, <<"Other room">>),
    {Question, Burn, Original} = send(Hub, Room, Access, <<"question">>, <<>>, 300000),
    {Child, ChildBurn, _} = send(Hub, Room, Access, <<"question">>, Question, 300000),
    {Poll, PollBurn, _} = send(Hub, Room, Access, <<"poll">>, <<>>, 300000),
    Pin = fun(A, O, Id) -> call(Hub, <<"POST">>, [<<"api">>, <<"spotlight">>], Room, A, O, <<>>, #{message_id => Id}) end,
    {403, _} = Pin(<<>>, Owner, Question),
    {403, _} = Pin(Access, <<>>, Question),
    {403, _} = Pin(Access, OtherOwner, Question),
    {400, _} = Pin(Access, Owner, Child),
    {400, _} = Pin(Access, Owner, 42),
    {404, _} = call(Hub, <<"POST">>, [<<"api">>, <<"spotlight">>], Other, OtherAccess, OtherOwner, <<>>, #{message_id => Question}),
    {200, Pinned} = Pin(Access, Owner, Question),
    Question = maps:get(<<"spotlight_id">>, Pinned),
    {200, _} = Pin(Access, Owner, Poll),
    1 = map_size(maps:get(spotlights, sys:get_state(Hub))),
    {200, _} = Pin(Access, Owner, Question),
    Resolve = [<<"api">>, <<"messages">>, Question, <<"resolve">>],
    {403, _} = call(Hub, <<"POST">>, Resolve, Room, <<>>, Owner, Burn, #{resolved => true}),
    {404, _} = call(Hub, <<"POST">>, Resolve, Room, Access, <<>>, PollBurn, #{resolved => true}),
    {404, _} = call(Hub, <<"POST">>, Resolve, Room, Access, OtherOwner, <<>>, #{resolved => true}),
    {400, _} = call(Hub, <<"POST">>, Resolve, Room, Access, <<>>, Burn, #{resolved => <<"true">>}),
    {400, _} = call(Hub, <<"POST">>, Resolve, Room, Access, <<>>, Burn, #{}),
    {200, Resolved} = call(Hub, <<"POST">>, Resolve, Room, Access, <<>>, Burn, #{resolved => true}),
    true = maps:get(<<"resolved">>, Resolved),
    lists:foreach(fun(K) -> V = maps:get(K, Original), V = maps:get(K, Resolved) end,
                  [<<"expires_at">>, <<"ttl_ms">>, <<"created_at">>]),
    {200, Reopened} = call(Hub, <<"POST">>, Resolve, Room, Access, Owner, <<>>, #{resolved => false}),
    false = maps:get(<<"resolved">>, Reopened),
    {400, _} = call(Hub, <<"POST">>, [<<"api">>, <<"messages">>, Child, <<"resolve">>], Room, Access, <<>>, ChildBurn, #{resolved => true}),
    PollState = [<<"api">>, <<"messages">>, Poll, <<"poll-state">>],
    Vote = [<<"api">>, <<"messages">>, Poll, <<"vote">>],
    {200, _} = call(Hub, <<"POST">>, Vote, Room, Access, <<>>, <<>>, #{option => 0}),
    {404, _} = call(Hub, <<"POST">>, PollState, Room, Access, <<>>, Burn, #{closed => true}),
    {400, _} = call(Hub, <<"POST">>, PollState, Room, Access, Owner, <<>>, #{closed => 1}),
    {200, Closed} = call(Hub, <<"POST">>, PollState, Room, Access, <<>>, PollBurn, #{closed => true}),
    true = maps:get(<<"poll_closed">>, Closed),
    {409, _} = call(Hub, <<"POST">>, Vote, Room, Access, <<>>, <<>>, #{option => 1}),
    {200, Open} = call(Hub, <<"POST">>, PollState, Room, Access, Owner, <<>>, #{closed => false}),
    [1, 0] = maps:get(<<"poll_counts">>, Open),
    {200, Voted} = call(Hub, <<"POST">>, Vote, Room, Access, <<>>, <<>>, #{option => 1}),
    [0, 1] = maps:get(<<"poll_counts">>, Voted),
    {200, _} = call(Hub, <<"DELETE">>, [<<"api">>, <<"messages">>, Question], Room, Access, <<>>, Burn, #{}),
    0 = map_size(maps:get(spotlights, sys:get_state(Hub))),
    % The operator key moderates public rooms, never private events it does not own.
    Global = binary:copy(<<"e">>, 48),
    sys:replace_state(Hub, fun(S) -> S#{moderator := spectre_link_ffi:hash(Global)} end),
    {403, _} = Pin(Access, Global, Poll),
    {Public, _, _} = send(Hub, <<"tools-public">>, <<>>, <<"thought">>, <<>>, 300000),
    {200, _} = call(Hub, <<"POST">>, [<<"api">>, <<"spotlight">>], <<"tools-public">>, <<>>, Global, <<>>, #{message_id => Public}),
    {200, _} = Pin(Access, Owner, Poll),
    {200, _} = call(Hub, <<"DELETE">>, [<<"api">>, <<"room">>], Room, Access, Owner, <<>>, #{}),
    false = maps:is_key(Room, maps:get(spotlights, sys:get_state(Hub))),
    gen_server:stop(Hub),
    nil.

spotlight_expiry() ->
    {ok, Hub} = spectre_link_hub:start_link(),
    {Room, Access, Owner} = event(Hub, <<"Independent spotlight expiry">>),
    {Id, _, _} = send(Hub, Room, Access, <<"thought">>, <<>>, 3000),
    {200, _} = call(Hub, <<"POST">>, [<<"api">>, <<"spotlight">>], Room, Access, Owner, <<>>, #{message_id => Id}),
    timer:sleep(3150),
    State = sys:get_state(Hub),
    0 = map_size(maps:get(spotlights, State)),
    0 = map_size(maps:get(messages, State)),
    gen_server:stop(Hub),
    nil.
