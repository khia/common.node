-module(common.node.boot_client).

-behaviour(application). 

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("debug.hrl").    
-include("internal.hrl").


%%--------------------------------------------------------------------
%% Import libraries
%%--------------------------------------------------------------------
-import(common.utils.lists, [errors/1]).
-import(common.utils.string).
-import(proplists).
-import(net_kernel).
-import(lists).
-import(inet).
-import(init).
-import(rpc).

-export([start/0, start_link/1]).
-export([start/2, stop/1]).

start_link(Args) ->
    start(undefined, Args). %% TODO move body from start/2
%%%----------------------------------------------------------------------
%%% Callback functions from application
%%%----------------------------------------------------------------------

start() ->
    start(normal, []).
-spec(start/2 :: (
	      Type :: normal | {takeover, node()} | {failover, node()}, 
	      Args :: term()) -> 
	     {ok, Pid :: pid()} 
		 | {ok, Pid :: pid(), State :: term()} 
		 | {error, Reason :: term()}).
start(Type, Args) -> 
    Self = proplists:get_value(self, Args, undefined),
    Default_Node_Name = 
	proplists:get_value(default_node_name, Args, ?default_client_node),
    Cookie = proplists:get_value(cookie, Args, ?default_client_cookie), 
%%    Server = proplists:get_value(server, Args, default_server()), 
    Server = node:boot_server(),

%%    Cookie = ?default_client_cookie, 
    erlang:disconnect_node(Default_Node_Name),
%    reattach(Default_Node_Name, Default_Node_Cookie),
    reattach(Default_Node_Name, Cookie),
    true = erlang:set_cookie(Server, Cookie),
    Node = get_node(),
    case register_client(Server, Default_Node_Name, Node) of
	{error, _Reason} = Error -> 
	    ?error("Cannot register client ~p",[Error], start),
	    Error;
	{Client, Session_Cookie} -> 
	    reattach(Client, Session_Cookie),
	    ?debug("!!",[],start),
	    {ok, self()}
    end.
    
-type(ignored() :: term()).
-spec(stop/1 :: (State :: term()) -> ignored()). 
stop(State) -> 
    ok.

default_server() ->
    %% FIXME
    {ok, Name} = inet:gethostname(),
    list_to_atom("rfidserver" ++ "@" ++ Name).

reattach(Server, Cookie) ->
    case node() of
	'nonode@nohost' -> skip;
	_Any -> 
	    ?debug("About to stop self ~p known nodes are ~p - ~p", 
		   [_Any, erlang:nodes(), net_kernel:stop()], reattach)	    
    end,
    ?debug("About to reattach(~p, ~p)", [Server, Cookie], reattach),
    case net_kernel:start([Server, shortnames]) of
	{ok, _Pid} -> 
	    ?debug("Node name was successfully changed",[],reattach),
	    erlang:set_cookie(Server, Cookie);
	Error -> Error
    end.

register_client(Server, Self, App) ->
    {ok, Host} = inet:gethostname(), %% never fails     
    ?debug("About to register client '~p:~p:~p' on server '~p'",
	   [App, Host, Self, Server],register_client),
    case rpc:call(Server, common.node.boot_server, register, 
		  [App, Host, Self]) of
	{badrpc, Reason} -> {error, Reason};
	{Client, _Session_Cookie} = Result -> Result
    end.

get_node() ->
    {ok, [[Id]]} = init:get_argument(id),
    get_node(Id).

%% Get a string with Id which is basically dot separated value 
%% and replace dots with underscore
get_node(Id) -> 
    Tokens = string:tokens(Id, "."),
    string:join(Tokens, "_").
    
    
