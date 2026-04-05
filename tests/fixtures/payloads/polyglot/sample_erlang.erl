-module(transmute_srv).
-behaviour(gen_server).
-export([start_link/0, init/1, handle_call/3]).

init(Args) ->
    {ok, Args}.

handle_call({transform, Data}, _From, State) ->
    Reply = binary_to_list(Data),
    {reply, Reply, State}.