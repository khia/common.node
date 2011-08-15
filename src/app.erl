-module(common.node.app).
-include("debug.hrl").
-include("utils.hrl").
-behaviour(application). 

-import(erlydb).
-import(proplists).
-import(erlang).
-import(common.node.node).

-export([start/2, stop/1]).

%%%----------------------------------------------------------------------
%%% Callback functions from application
%%%----------------------------------------------------------------------
-define(APPLICATION, .string:split(?MODULE_STRING).

-spec(start/2 :: (
	      Type :: normal | {takeover, node()} | {failover, node()}, 
	      Args :: term()) -> 
	     {ok, Pid :: pid()} 
		 | {ok, Pid :: pid(), State :: term()} 
		 | {error, Reason :: term()}).
start(_Type, Args) -> 
    case sup:start_link(Args) of
	{ok, Pid} -> 
	    ?debug("Application ~p was successfully started.", 
		   [?APP_STRING], start),
	    {ok, Pid};
	Error -> 
	    ?debug("Cannot start application ~p, reason ~p.", 
		   [?APP_STRING, Error], start),
	    Error
    end.

-type(ignored() :: term()).
-spec(stop/1 :: (State :: term()) -> ignored()). 
stop(_State) -> 
    ok.

