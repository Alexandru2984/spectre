%% Bounded OTP state. Room authorization and mutations are serialized.
%% Reserved managed IDs fail closed; child expiry and removal cascade.
-module(spectre_link_hub).
-behaviour(gen_server).
-compile({no_auto_import, [{now, 0}]}).
-export([start_link/0,
         request/11,
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2, format_status/1]).
start_link() ->
    gen_server:start_link(spectre_link_hub, [], []).
request(Hub, Method, Path, Room, Access, Moderator, Client, Address,
        Since, Burn, Body) ->
    try
        Data =
            case Body of
                <<>> ->
                    #{};
                _ ->
                    json:decode(Body)
            end,
        case is_map(Data) of
            true ->
                ok;
            false ->
                throw({http, 400, <<"Expected a JSON object.">>})
        end,
        Request =
            #{method => Method,
              path => Path,
              room => Room,
              access => digest(Access),
              mod => digest(Moderator),
              client => Client,
              address => Address,
              since => Since,
              burn => digest(Burn),
              data => Data},
        gen_server:call(Hub, {api, Request}, 23000)
    catch
        throw:{http, Code, Message} ->
            response(Code, #{error => Message});
        exit:{timeout, _} ->
            response(503, #{error => <<"Please reconnect.">>});
        _:_ ->
            response(400, #{error => <<"Invalid request or JSON.">>})
    end.
init([]) ->
    process_flag(trap_exit, true),
    erlang:send_after(500, self(), sweep),
    Key = spectre_link_ffi:env(<<"SPECTRE_MODERATOR_KEY">>, <<>>),
    Mod =
        case spectre_link_ffi:valid_token(Key) of
            true ->
                digest(Key);
            false ->
                <<>>
        end,
    {ok,
     #{messages => #{},
       rooms => #{},
       sessions => #{},
       waiters => #{},
       reports => #{},
       versions => #{},
       moderator => Mod}}.
handle_call({api, Q}, From, Old) ->
    S = clean(Old),
    try dispatch(Q, From, S) of
        {wait, Next} ->
            {noreply, Next};
        {Code, Data, Next} ->
            {reply, response(Code, Data), notify(Next)}
    catch
        throw:{http, Code, Message} ->
            {reply, response(Code, #{error => Message}), S};
        _:_ ->
            {reply,
             response(500,
                      #{error => <<"Unable to complete this request.">>}),
             S}
    end;
handle_call(_, _, S) ->
    {reply, response(400, #{error => <<"Invalid request.">>}), S}.
handle_cast(_, S) ->
    {noreply, S}.
handle_info(sweep, S) ->
    erlang:send_after(500, self(), sweep),
    {noreply, notify(clean(S))};
handle_info({expire, Id}, S) ->
    {noreply, notify(remove_messages([Id], S))};
handle_info({'EXIT', Pid, normal}, S) ->
    Ids =
        [
         I ||
             {I, M} <- maps:to_list(maps:get(messages, S)),
             maps:get(pid, M) =:= Pid
        ],
    {noreply, notify(remove_messages(Ids, S))};
handle_info({'EXIT', _, _}, S) ->
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.
dispatch(#{method := <<"POST">>,
           path := [<<"api">>, <<"rooms">>],
           data := D} =
             Q,
         _, S) ->
    ensure(map_size(maps:get(rooms, S)) < 256,
           503,
           <<"Room capacity reached. Try again after an event ends.">>),
    Label = text(D, <<"name">>, 1, 48),
    Topic = optional_text(D, <<"topic">>, 120),
    Minutes = maps:get(<<"minutes">>, D, 30),
    ensure(lists:member(Minutes, [15, 30, 60]),
           400,
           <<"Choose a 15, 30 or 60 minute event.">>),
    Private = boolean(D, <<"private">>, false),
    Encrypted = boolean(D, <<"encrypted">>, false),
    Discover = boolean(D, <<"discoverable">>, false),
    ensure(not (Private
                andalso
                Discover),
           400,
           <<"Private rooms cannot be listed.">>),
    ensure(not Encrypted
           orelse
           Private,
           400,
           <<"Encryption requires a private room.">>),
    Client = client(Q),
    Owned =
        length([
                R ||
                    R <- maps:values(maps:get(rooms, S)),
                    maps:get(creator, R) =:= digest(Client)
               ]),
    ensure(Owned < 5, 429, <<"You can own up to five active rooms.">>),
    Address = maps:get(address, Q),
    OwnedAtAddress =
        length([
                R ||
                    R <- maps:values(maps:get(rooms, S)),
                    maps:get(creator_address, R, none) =:= Address
               ]),
    ensure(OwnedAtAddress < 10,
           429,
           <<"Too many active events from this address.">>),
    Id = <<"r-",(binary:part(random(), 0, 24))/binary>>,
    Owner = random(),
    Reader = random(),
    R = #{id => Id,
          name => Label,
          topic => Topic,
          private => Private,
          encrypted => Encrypted,
          discoverable => Discover,
          owner => digest(Owner),
          reader => digest(Reader),
          creator => digest(Client),
          creator_address => Address,
          deadline => mono() + Minutes * 60000,
          expires_at => now() + Minutes * 60000},
    Next = bump(Id, S#{rooms := maps:put(Id, R, maps:get(rooms, S))}),
    {201,
     #{room => room_view(R, Next, Q),
       owner_key => Owner,
       access_key =>
           case Private of
               true ->
                   Reader;
               false ->
                   <<>>
           end},
     Next};
dispatch(#{method := <<"GET">>, path := [<<"api">>, <<"rooms">>]} = Q,
         _, S) ->
    Defaults =
        [
         room_view(default_room(Id), S, Q) ||
             Id <- builtin()
        ],
    Listed =
        [
         room_view(R, S, Q) ||
             R <- maps:values(maps:get(rooms, S)),
             maps:get(discoverable, R)
             andalso
             not maps:get(private, R)
        ],
    {200, Defaults ++ Listed, S};
dispatch(#{method := <<"GET">>, path := [<<"api">>, <<"nodes">>]}, _, S) ->
    {200, [<<"local">>], S};
dispatch(Q, From, S) ->
    Room0 = maps:get(room, Q),
    D = maps:get(data, Q),
    Room =
        case {maps:get(method, Q), maps:get(path, Q)} of
            {<<"POST">>, [<<"api">>, <<"messages">>]} ->
                maps:get(<<"room">>, D, <<"lobby">>);
            _ ->
                Room0
        end,
    ensure(is_binary(Room)
           andalso
           spectre_link_ffi:valid_room_name(Room),
           400,
           <<"Invalid room name.">>),
    R = get_room(Room, S),
    access(R, Q),
    room_dispatch(Q#{room := Room}, From, R, S).
room_dispatch(#{method := <<"GET">>,
                path := [<<"api">>, <<"snapshot">>],
                room := Room} =
                  Q,
              _, R, S) ->
    {200,
     #{messages =>
           [
            public_message(M) ||
                M <- room_messages(Room, S)
           ],
       room => room_view(R, S, Q),
       presence => presence(Room, S)},
     S};
room_dispatch(#{method := <<"GET">>,
                path := [<<"api">>, <<"messages">>],
                room := Room},
              _, _, S) ->
    {200,
     [
      public_message(M) ||
          M <- room_messages(Room, S)
     ],
     S};
room_dispatch(#{method := <<"GET">>, path := [<<"api">>, <<"stats">>]} =
                  Q,
              _, R, S) ->
    {200, room_view(R, S, Q), S};
room_dispatch(#{method := <<"GET">>, path := [<<"api">>, <<"room">>]} =
                  Q,
              _, R, S) ->
    {200, room_view(R, S, Q), S};
room_dispatch(#{method := <<"DELETE">>,
                path := [<<"api">>, <<"room">>],
                room := Room} =
                  Q,
              _, R, S) ->
    ensure(managed(Room)
           andalso
           is_owner(R, Q),
           403,
           <<"Room owner capability required.">>),
    {200, #{status => <<"closed">>}, close_room(Room, S)};
room_dispatch(#{method := <<"POST">>,
                path := [<<"api">>, <<"messages">>],
                data := D,
                room := Room},
              _, R, S) ->
    Messages = maps:get(messages, S),
    ensure(map_size(Messages) < 500
           andalso
           length(room_messages(Room, S)) < 100,
           503,
           <<"This room or server is at capacity. Try again after messa"
             "ges expire.">>),
    Kind = maps:get(<<"kind">>, D, <<"thought">>),
    ensure(lists:member(Kind,
                        [<<"thought">>,
                         <<"idea">>,
                         <<"question">>,
                         <<"poll">>]),
           400,
           <<"Choose thought, idea, question or poll.">>),
    TTL = maps:get(<<"ttl">>, D, 0),
    ensure(is_integer(TTL)
           andalso
           TTL >= 3000
           andalso
           TTL =< 300000,
           400,
           <<"Lifetime must be between 3 and 300 seconds.">>),
    Encrypted = boolean(D, <<"encrypted">>, false),
    ensure(Encrypted =:= maps:get(encrypted, R),
           400,
           <<"Message encryption must match the room.">>),
    Content =
        case Encrypted of
            false ->
                {ok, Base} =
                    case
                        spectre_link@validation:parse_message(iolist_to_binary(json:encode(D)))
                    of
                        {ok, _} = OK ->
                            OK;
                        {error, Msg} ->
                            throw({http, 400, Msg})
                    end,
                element(2, Base);
            true ->
                ciphertext(D)
        end,
    Options = maps:get(<<"options">>, D, []),
    ensure(is_list(Options), 400, <<"Poll options must be an array.">>),
    case Kind of
        <<"poll">> ->
            ensure(length(Options) >= 2
                   andalso
                   length(Options) =< 6
                   andalso
                   length(lists:usort(Options)) =:= length(Options),
                   400,
                   <<"A poll needs 2-6 distinct options.">>),
            [
             ensure(valid_text(O, 1, 100),
                    400,
                    <<"Poll options must contain 1-100 character"
                      "s.">>) ||
                 O <- Options
            ];
        _ ->
            ensure(Options =:= [],
                   400,
                   <<"Only polls can have options.">>)
    end,
    Parent = maps:get(<<"parent_id">>, D, <<>>),
    ensure(is_binary(Parent), 400, <<"Invalid parent message.">>),
    MonoCreated = mono(),
    WallCreated = now(),
    {ParentDeadline, ParentExpires} =
        case Parent of
            <<>> ->
                {MonoCreated + TTL, WallCreated + TTL};
            _ ->
                PM = message(Parent, Room, S),
                ensure(maps:get(parent_id, PM) =:= <<>>,
                       400,
                       <<"Reply to the main message; nested reply depth"
                         " is limited to one.">>),
                ensure(length([
                               M ||
                                   M <- maps:values(Messages),
                                   maps:get(parent_id, M) =:= Parent
                              ])
                       <
                       30,
                       503,
                       <<"This thread has reached its reply limit.">>),
                {maps:get(deadline, PM), maps:get(expires_at, PM)}
        end,
    Deadline = min(MonoCreated + TTL, min(ParentDeadline, maps:get(deadline, R))),
    Remaining = Deadline - MonoCreated,
    RoomExpires = case maps:get(expires_at, R) of 0 -> WallCreated + Remaining; Value -> Value end,
    Expires = min(WallCreated + Remaining, min(ParentExpires, RoomExpires)),
    ActualTTL = Expires - WallCreated,
    ensure(ActualTTL > 0, 410, <<"This conversation has ended.">>),
    Author = optional_text(D, <<"author">>, 24),
    Id = random(),
    Key = random(),
    {ok, Pid} = spectre_link_message:start_link(self(), Id, Deadline),
    M = #{id => Id,
          room => Room,
          kind => Kind,
          content => Content,
          encrypted => Encrypted,
          parent_id => Parent,
          author => Author,
          options => Options,
          poll_votes => #{},
          votes => #{},
          burn => digest(Key),
          created_at => WallCreated,
          ttl_ms => ActualTTL,
          expires_at => Expires,
          deadline => Deadline,
          pid => Pid},
    Next = bump(Room, S#{messages := maps:put(Id, M, Messages)}),
    {201,
     #{id => Id, burn_key => Key, message => public_message(M)},
     Next};
room_dispatch(#{method := <<"DELETE">>,
                path := [<<"api">>, <<"messages">>, Id],
                room := Room,
                mod := Mod} =
                  Q,
              _, R, S) ->
    M = message(Id, Room, S),
    Burn = maps:get(burn, Q, <<>>),
    ensure(Burn =:= maps:get(burn, M)
           orelse
           moderator(R, Q, S),
           404,
           <<"Message or burn capability not found.">>),
    _ = Mod,
    {200, #{status => <<"burned">>}, remove_messages([Id], S)};
room_dispatch(#{method := <<"POST">>,
                path := [<<"api">>, <<"messages">>, Id, <<"reactions">>],
                room := Room,
                data := D} =
                  Q,
              _, _, S) ->
    M = message(Id, Room, S),
    C = digest(client(Q)),
    Emoji = maps:get(<<"emoji">>, D, <<>>),
    ensure(lists:member(Emoji,
                        [<<"spark">>, <<"heart">>, <<"curious">>]),
           400,
           <<"Unknown reaction.">>),
    Votes = maps:get(votes, M),
    ensure(map_size(Votes) < 256
           orelse
           maps:is_key(C, Votes),
           429,
           <<"Reaction capacity reached.">>),
    New =
        case maps:get(C, Votes, none) of
            Emoji ->
                maps:remove(C, Votes);
            _ ->
                maps:put(C, Emoji, Votes)
        end,
    Updated = M#{votes := New},
    {200, public_message(Updated), put_message(Updated, S)};
room_dispatch(#{method := <<"POST">>,
                path := [<<"api">>, <<"messages">>, Id, <<"vote">>],
                room := Room,
                data := D} =
                  Q,
              _, _, S) ->
    M = message(Id, Room, S),
    ensure(maps:get(kind, M) =:= <<"poll">>,
           400,
           <<"This message is not a poll.">>),
    Index = maps:get(<<"option">>, D, -1),
    ensure(is_integer(Index)
           andalso
           Index >= 0
           andalso
           Index < length(maps:get(options, M)),
           400,
           <<"Invalid poll option.">>),
    C = digest(client(Q)),
    Votes = maps:get(poll_votes, M),
    ensure(map_size(Votes) < 256
           orelse
           maps:is_key(C, Votes),
           429,
           <<"Poll voter capacity reached.">>),
    Updated = M#{poll_votes := maps:put(C, Index, Votes)},
    {200, public_message(Updated), put_message(Updated, S)};
room_dispatch(#{method := <<"POST">>,
                path := [<<"api">>, <<"messages">>, Id, <<"report">>],
                room := Room,
                data := D} =
                  Q,
              _, _, S) ->
    _ = message(Id, Room, S),
    Reason = maps:get(<<"reason">>, D, <<"spam">>),
    ensure(lists:member(Reason,
                        [<<"spam">>,
                         <<"harassment">>,
                         <<"sensitive">>,
                         <<"other">>]),
           400,
           <<"Choose a report reason.">>),
    C = digest(client(Q)),
    Reports = maps:get(reports, S),
    Report = maps:get(Id, Reports, #{room => Room, reporters => #{}}),
    Reporters = maps:get(reporters, Report),
    ensure(map_size(Reporters) < 64
           orelse
           maps:is_key(C, Reporters),
           429,
           <<"Report capacity reached.">>),
    ensure(map_size(Reports) < 500
           orelse
           maps:is_key(Id, Reports),
           503,
           <<"Report capacity reached.">>),
    Next =
        bump(Room,
             S#{reports :=
                    maps:put(Id,
                             Report#{reporters :=
                                         maps:put(C, Reason, Reporters)},
                             Reports)}),
    {200, #{status => <<"reported">>}, Next};
room_dispatch(#{method := <<"GET">>,
                path := [<<"api">>, <<"reports">>],
                room := Room} =
                  Q,
              _, R, S) ->
    ensure(moderator(R, Q, S),
           403,
           <<"Moderator capability required.">>),
    Reports =
        [
         #{id => Id,
           count => map_size(maps:get(reporters, V)),
           reasons => counts(maps:values(maps:get(reporters, V))),
           message => public_message(message(Id, Room, S))} ||
             {Id, V} <- maps:to_list(maps:get(reports, S)),
             maps:get(room, V) =:= Room
        ],
    {200, Reports, S};
room_dispatch(#{method := <<"POST">>,
                path := [<<"api">>, <<"presence">>],
                room := Room,
                data := D} =
                  Q,
              _, _, S) ->
    C = digest(client(Q)),
    Key = {Room, C},
    Sessions = maps:get(sessions, S),
    ensure(map_size(Sessions) < 1000
           orelse
           maps:is_key(Key, Sessions),
           503,
           <<"Presence capacity reached.">>),
    ensure(length([
                   V ||
                       {{Rm, _}, V} <- maps:to_list(Sessions),
                       Rm =:= Room
                  ])
           <
           100
           orelse
           maps:is_key(Key, Sessions),
           503,
           <<"This room has reached its session limit.">>),
    Alias = optional_text(D, <<"alias">>, 24),
    Existing = maps:get(Key, Sessions, #{}),
    Entry = #{alias => Alias, deadline => mono() + 45000},
    Next0 = S#{sessions := maps:put(Key, Entry, Sessions)},
    Next =
        case maps:get(alias, Existing, none) =:= Alias of
            true ->
                Next0;
            false ->
                bump(Room, Next0)
        end,
    {200, presence(Room, Next), Next};
room_dispatch(#{method := <<"DELETE">>,
                path := [<<"api">>, <<"presence">>],
                room := Room} =
                  Q,
              _, _, S) ->
    Key = {Room, digest(client(Q))},
    Next =
        bump(Room,
             S#{sessions := maps:remove(Key, maps:get(sessions, S))}),
    {200, #{status => <<"left">>}, Next};
room_dispatch(#{method := <<"GET">>,
                path := [<<"api">>, <<"presence">>],
                room := Room},
              _, _, S) ->
    {200, presence(Room, S), S};
room_dispatch(#{method := <<"GET">>,
                path := [<<"api">>, <<"events">>],
                room := Room,
                since := Since,
                address := Addr},
              From, _, S) ->
    Version = version(Room, S),
    Parsed =
        try
            binary_to_integer(Since)
        catch
            _:_ ->
                -1
        end,
    case Parsed =/= Version of
        true ->
            {200, #{revision => Version}, S};
        false ->
            Ws = maps:get(waiters, S),
            ensure(map_size(Ws) < 100
                   andalso
                   length([
                           W ||
                               W <- maps:values(Ws),
                               maps:get(room, W) =:= Room
                          ])
                   <
                   30,
                   503,
                   <<"Live connection capacity reached.">>),
            ensure(length([
                           W ||
                               W <- maps:values(Ws),
                               maps:get(address, W) =:= Addr
                          ])
                   <
                   4,
                   429,
                   <<"Too many live connections from this address.">>),
            W = #{room => Room,
                  version => Version,
                  from => From,
                  deadline => mono() + 20000,
                  address => Addr},
            {wait, S#{waiters := maps:put(make_ref(), W, Ws)}}
    end;
room_dispatch(_, _, _, S) ->
    {405, #{error => <<"Method not allowed.">>}, S}.
get_room(Id, S) ->
    case maps:find(Id, maps:get(rooms, S)) of
        {ok, R} ->
            R;
        error ->
            ensure(not managed(Id),
                   404,
                   <<"This room has ended or does not exist.">>),
            default_room(Id)
    end.
default_room(Id) ->
    #{id => Id,
      name => Id,
      topic => <<>>,
      private => false,
      encrypted => false,
      discoverable => lists:member(Id, builtin()),
      owner => <<>>,
      reader => <<>>,
      deadline => mono() + 86400000,
      expires_at => 0}.
managed(<<"r-",_/binary>>) ->
    true;
managed(_) ->
    false.
builtin() ->
    [<<"lobby">>, <<"ideas">>, <<"questions">>, <<"after-hours">>].
access(#{private := false}, _) ->
    ok;
access(R, Q) ->
    ensure(maps:get(access, Q) =:= maps:get(reader, R),
           403,
           <<"A valid private room invitation is required.">>).
is_owner(R, Q) ->
    maps:get(owner, R) =/= <<>>
    andalso
    maps:get(owner, R) =:= maps:get(mod, Q).
moderator(R, Q, S) ->
    is_owner(R, Q)
    orelse
    not maps:get(private, R)
    andalso
    maps:get(moderator, S) =/= <<>>
    andalso
    maps:get(mod, Q) =:= maps:get(moderator, S).
room_view(R, S, Q) ->
    Id = maps:get(id, R),
    (maps:with([id, name, topic, private, encrypted, discoverable,
                expires_at],
               R))#{active => length(room_messages(Id, S)),
                    sessions => maps:get(count, presence(Id, S)),
                    room_limit => 100,
                    max_ttl_ms => 300000,
                    revision => version(Id, S),
                    can_moderate => moderator(R, Q, S),
                    is_owner => is_owner(R, Q)}.
room_messages(Room, S) ->
    [
     M ||
         M <- maps:values(maps:get(messages, S)),
         maps:get(room, M) =:= Room
    ].
message(Id, Room, S) ->
    case maps:find(Id, maps:get(messages, S)) of
        {ok, #{room := Room} = M} ->
            M;
        _ ->
            throw({http, 404,
                   <<"Message has expired or does not exist in this roo"
                     "m.">>})
    end.
public_message(M) ->
    Base =
        maps:with([id, room, kind, content, parent_id, author,
                   encrypted, created_at, expires_at, ttl_ms, options],
                  M),
    Votes = maps:get(poll_votes, M),
    N = length(maps:get(options, M)),
    Base#{reactions =>
              maps:merge(#{<<"spark">> => 0,
                           <<"heart">> => 0,
                           <<"curious">> => 0},
                         counts(maps:values(maps:get(votes, M)))),
          poll_counts =>
              [
               length([
                       V ||
                           V <- maps:values(Votes),
                           V =:= I
                      ]) ||
                   I <- lists:seq(0, N - 1)
              ],
          poll_total => map_size(Votes)}.
put_message(M, S) ->
    bump(maps:get(room, M),
         S#{messages :=
                maps:put(maps:get(id, M), M, maps:get(messages, S))}).
counts(Items) ->
    lists:foldl(fun(K, A) ->
                       maps:update_with(K,
                                        fun(N) ->
                                               N + 1
                                        end,
                                        1, A)
                end,
                #{},
                Items).
presence(Room, S) ->
    Entries =
        [
         V ||
             {{Rm, _}, V} <- maps:to_list(maps:get(sessions, S)),
             Rm =:= Room
        ],
    #{count => length(Entries),
      aliases =>
          lists:usort([
                       maps:get(alias, V) ||
                           V <- Entries,
                           maps:get(alias, V) =/= <<>>
                      ])}.
version(Room, S) ->
    maps:get(Room, maps:get(versions, S), 0).
bump(Room, S) ->
    S#{versions :=
           maps:put(Room, version(Room, S) + 1, maps:get(versions, S))}.
clean(S) ->
    Now = mono(),
    Closed =
        [
         Id ||
             {Id, R} <- maps:to_list(maps:get(rooms, S)),
             maps:get(deadline, R) =< Now
        ],
    S1 = lists:foldl(fun close_room/2, S, Closed),
    Dead =
        [
         Id ||
             {Id, M} <- maps:to_list(maps:get(messages, S1)),
             maps:get(deadline, M) =< Now
             orelse
             not is_process_alive(maps:get(pid, M))
        ],
    S2 = remove_messages(Dead, S1),
    Sessions = maps:get(sessions, S2),
    OldSessions =
        [
         Room ||
             {{Room, _}, V} <- maps:to_list(Sessions),
             maps:get(deadline, V) =< Now
        ],
    S3 =
        S2#{sessions :=
                maps:filter(fun(_, V) ->
                                   maps:get(deadline, V) > Now
                            end,
                            Sessions)},
    lists:foldl(fun bump/2, S3, lists:usort(OldSessions)).
close_room(Room, S) ->
    Ids =
        [
         maps:get(id, M) ||
             M <- room_messages(Room, S)
        ],
    S1 = remove_messages(Ids, S),
    bump(Room,
         S1#{rooms := maps:remove(Room, maps:get(rooms, S1)),
             sessions :=
                 maps:filter(fun({Rm, _}, _) ->
                                    Rm =/= Room
                             end,
                             maps:get(sessions, S1))}).
remove_messages([], S) ->
    S;
remove_messages(Ids, S) ->
    Messages = maps:get(messages, S),
    Children =
        [
         I ||
             {I, M} <- maps:to_list(Messages),
             lists:member(maps:get(parent_id, M), Ids)
        ],
    All = lists:usort(Ids ++ Children),
    Rooms =
        lists:usort([
                     maps:get(room, M) ||
                         I <- All,
                         {ok, M} <- [maps:find(I, Messages)]
                    ]),
    [
     spectre_link_message:stop(maps:get(pid, M)) ||
         I <- All,
         {ok, M} <- [maps:find(I, Messages)]
    ],
    S1 =
        S#{messages := maps:without(All, Messages),
           reports := maps:without(All, maps:get(reports, S))},
    lists:foldl(fun bump/2, S1, Rooms).
notify(S) ->
    Now = mono(),
    Waiters =
        maps:filter(fun(_, W) ->
                           {Pid, _} = maps:get(from, W),
                           Room = maps:get(room, W),
                           case is_process_alive(Pid) of
                               false ->
                                   false;
                               true ->
                                   case
                                       version(Room, S)
                                       =/=
                                       maps:get(version, W)
                                       orelse
                                       maps:get(deadline, W) =< Now
                                   of
                                       true ->
                                           gen_server:reply(maps:get(from,
                                                                     W),
                                                            response(200,
                                                                     #{revision =>
                                                                           version(Room,
                                                                                   S)})),
                                           false;
                                       false ->
                                           true
                                   end
                           end
                    end,
                    maps:get(waiters, S)),
    Live =
        lists:usort(builtin()
                    ++
                    maps:keys(maps:get(rooms, S))
                    ++
                    [
                     maps:get(room, M) ||
                         M <- maps:values(maps:get(messages, S))
                    ]
                    ++
                    [
                     Room ||
                         {{Room, _}, _} <-
                             maps:to_list(maps:get(sessions, S))
                    ]
                    ++
                    [
                     maps:get(room, W) ||
                         W <- maps:values(Waiters)
                    ]),
    S#{waiters := Waiters,
       versions := maps:with(Live, maps:get(versions, S))}.
client(Q) ->
    C = maps:get(client, Q),
    ensure(spectre_link_ffi:valid_token(C),
           400,
           <<"A valid X-Spectre-Client token is required.">>),
    C.
text(D, K, Min, Max) ->
    V = maps:get(K, D, <<>>),
    ensure(valid_text(V, Min, Max),
           400,
           <<"Text is empty, too long or contains unsupported controls.">>),
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(V))).
optional_text(D, K, Max) ->
    case maps:get(K, D, <<>>) of
        <<>> ->
            <<>>;
        _ ->
            text(D, K, 1, Max)
    end.
valid_text(V, Min, Max) when is_binary(V), byte_size(V) =< Max * 4 ->
    case unicode:characters_to_list(V) of
        L when is_list(L) ->
            N = string:length(string:trim(L)),
            N >= Min
            andalso
            N =< Max
            andalso
            not spectre_link_ffi:has_unsafe_controls(V);
        _ ->
            false
    end;
valid_text(_, _, _) ->
    false.
boolean(D, K, Default) ->
    V = maps:get(K, D, Default),
    ensure(is_boolean(V), 400, <<"Expected a boolean field.">>),
    V.
ciphertext(D) ->
    Value = maps:get(<<"content">>, D, <<>>),
    ensure(is_binary(Value)
           andalso
           byte_size(Value) > 20
           andalso
           byte_size(Value) =< 7000,
           400,
           <<"Invalid encrypted message envelope.">>),
    E = try
            json:decode(Value)
        catch
            _:_ ->
                throw({http, 400,
                       <<"Invalid encrypted message envelope.">>})
        end,
    ensure(is_map(E)
           andalso
           maps:get(<<"v">>, E, 0) =:= 1
           andalso
           is_binary(maps:get(<<"iv">>, E, none))
           andalso
           is_binary(maps:get(<<"ciphertext">>, E, none)),
           400,
           <<"Invalid encrypted message envelope.">>),
    ensure(byte_size(maps:get(<<"iv">>, E)) =:= 16
           andalso
           byte_size(maps:get(<<"ciphertext">>, E)) >= 22,
           400,
           <<"Invalid encrypted message envelope.">>),
    Value.
ensure(true, _, _) ->
    ok;
ensure(false, Code, Message) ->
    throw({http, Code, Message}).
response(Code, Data) ->
    {Code, iolist_to_binary(json:encode(Data))}.
digest(<<>>) ->
    <<>>;
digest(Value) ->
    spectre_link_ffi:hash(Value).
random() ->
    spectre_link_ffi:random_id().
mono() ->
    erlang:monotonic_time(millisecond).
now() ->
    erlang:system_time(millisecond).

%% OTP diagnostics must not dump active content or request capabilities.
format_status(Status) ->
    maps:map(fun(Key,Value) ->
        case Key of
            state -> #{redacted => true};
            message -> redacted;
            reason -> redacted;
            log -> [];
            _ -> Value
        end
    end,Status).
