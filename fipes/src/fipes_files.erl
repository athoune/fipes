-module(fipes_files).
-behaviour(cowboy_http_handler).

-export([init/3, handle/2, terminate/2]).


init({_Any, http}, Req, []) ->
    {ok, Req, []}.


handle(Req, State) ->
    {ok, Req2} = dispatch(Req),
    {ok, Req2, State}.


dispatch(Req) ->
    {Fipe, Req} = cowboy_http_req:binding(pipe, Req),
    case cowboy_http_req:method(Req) of
        {'GET', Req} ->
            case cowboy_http_req:binding(file, Req) of
                {undefined, Req} ->
                    index(Fipe, Req);
                {File, Req} ->
                    download(Fipe, File, Req)
            end;
        {'POST', Req} ->
            create(Fipe, Req)
    end.


index(Fipe, Req) ->
    Headers    = [{<<"Content-Type">>, <<"application/tnetstrings">>}],

    Objects    = ets:match_object(files, {{Fipe, '_'}, '_'}),
    FilesInfos = [{struct, FileInfos} ||
                     {{Fipe, _FileId}, {_Owner, FileInfos}} <- Objects],
    Results    = tnetstrings:encode(FilesInfos, [{label, atom}]),

    cowboy_http_req:reply(200, Headers, Results, Req).


download(Fipe, File, Req) ->
    % Register the downloader
    Uid = fipes_utils:token(8),
    ets:insert(downloaders, {{Fipe, Uid}, self()}),

    Name = name(Fipe, File),

    Headers =
        [{<<"Content-Type">>,        <<"application/octet-stream">>},
         {<<"Content-Disposition">>, [<<"attachment; filename=\"">>, Name, <<"\"">>]},
         % Says to Nginx to not buffer this response
         % http://wiki.nginx.org/X-accel#X-Accel-Buffering
         {<<"X-Accel-Buffering">>,   <<"no">>}
        ],
    {ok, Req2} = cowboy_http_req:chunked_reply(200, Headers, Req),

    % Ask the file owner to start the stream
    Owner = owner(Fipe, File),
    Owner ! {stream, File, Uid, 0},

    stream(Fipe, File, Owner, Uid, Req2).


owner(Fipe, File) ->
    [{{Fipe, File}, {Uid, _FileInfos}}] = ets:lookup(files, {Fipe, File}),
    [{{Fipe, Uid}, Owner}] = ets:lookup(owners, {Fipe, Uid}),
    Owner.

name(Fipe, File) ->
    [{{Fipe, File}, {_Uid, FileInfos}}] = ets:lookup(files, {Fipe, File}),
    proplists:get_value(name, FileInfos).


stream(Fipe, File, Owner, Uid, Req) ->
    receive
        {chunk, eos} ->
            ets:delete(downloaders, {Fipe, Uid}),
            {ok, Req};
        {chunk, FirstChunk} ->
            <<SmallChunk:1/binary, NextCurrentChunk/binary>> = FirstChunk,
            cowboy_http_req:chunk(SmallChunk, Req),
            NextSeek = size(FirstChunk),
            Owner ! {stream, File, Uid, NextSeek},
            stream(Fipe, File, Owner, Uid, NextCurrentChunk, NextSeek, Req)
    end.
stream(Fipe, File, Owner, Uid, CurrentChunk, Seek, Req) ->
    receive
        {chunk, eos} ->
            cowboy_http_req:chunk(CurrentChunk, Req),
            ets:delete(downloaders, {Fipe, Uid}),
            {ok, Req};
        {chunk, NextChunk} ->
            cowboy_http_req:chunk(CurrentChunk, Req),
            NextSeek = Seek + size(NextChunk),
            Owner ! {stream, File, Uid, NextSeek},
            stream(Fipe, File, Owner, Uid, NextChunk, NextSeek, Req)
    after
        20000 ->
            <<SmallChunk:1/binary, NexCurrentChunk/binary>> = CurrentChunk,
            cowboy_http_req:chunk(SmallChunk, Req),
            stream(Fipe, File, Owner, Uid, NexCurrentChunk, Seek, Req)
    end.


create(Fipe, Req) ->
    {FileId, Owner, FileInfos} = file_infos(Req),
    true = ets:insert(files, {{Fipe, FileId}, {Owner, FileInfos}}),

    notify(Fipe, FileInfos),

    Headers = [{<<"Content-Type">>, <<"application/tnetstrings">>}],
    Result  = tnetstrings:encode({struct, FileInfos}),
    cowboy_http_req:reply(200, Headers, Result, Req).


file_infos(Req) ->
    FileId = fipes_utils:token(2),

    {ok, Body, Req2} = cowboy_http_req:body(Req),
    {struct, FileInfos} = tnetstrings:decode(Body, [{label, atom}]),
    Owner = proplists:get_value(owner, FileInfos),

    {FileId, Owner, [{id, FileId}|FileInfos]}.

notify(Fipe, FileInfos) ->
    [Owner ! {new, FileInfos} ||
        {{OtherFipe, Uid}, Owner} <- ets:tab2list(owners), OtherFipe == Fipe],
    ok.


terminate(_Req, _State) ->
    ok.

