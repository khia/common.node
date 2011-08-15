-module(common.node.code).

-behaviour(gen_server). 

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("debug.hrl").
-include("utils.hrl").
-include("internal.hrl").

%%--------------------------------------------------------------------
%% Import libraries
%%--------------------------------------------------------------------
-import(lists).
-import(erlang).
-import(gen_server).
-import(code).
-import(filelib).
-import(beam_lib).

%%--------------------------------------------------------------------
%% API

%% Public API
-export([
	 get_all_beams/0,
	 get_modules_with_fun/2
	 ]).

%% Server Control
-export([stop/0, stop/1, start_link/0, start_link/1, status/0, status/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, 
	 handle_info/2,
	 terminate/2, code_change/3]).

%% -type(now() :: {Mega :: integer(), Sec :: integer(), Micro :: integer()}).
%% -record(node, {id :: string(), 
%% 	       idx :: integer(), 
%% 	       host :: atom(), 
%% 	       value :: atom(),
%% 	       cookie :: string(),
%% 	       ts :: now()}).

-record(state, {}).

%% @spec get_all_beams() -> [ListOfFiles::string()]
%% @doc  Function determines the list of path that is known by the system 
%%     and get list of beam files that was found in each directory.
get_all_beams()->
    Path=code:get_path(),
    get_all_beams(Path, []).

get_all_beams([], Res)->
    Res;

get_all_beams([Dir | List_Of_Directories], Res)->
    %% Fix me this will works only for my release structure
    Files=case filelib:wildcard(Dir ++ "/*/*/*/*.beam") of
	      [] -> [];
	      List -> List
	  end,
    get_all_beams(List_Of_Directories, Files ++ Res).

get_modules_with_fun(Fun, Arity) ->
    AllBeams=get_all_beams(),
    get_modules_with_fun(AllBeams, Fun, Arity).
    
get_modules_with_fun(ListOfFiles, Fun, Arity) when is_list(ListOfFiles)->
    get_modules_with_fun(ListOfFiles, Fun, Arity, []).

get_modules_with_fun([], Fun, Arity, Result) -> Result;

get_modules_with_fun([Module | ListOfFiles], Fun, Arity, Result) 
  when is_list(ListOfFiles)->
    Res=case beam_lib:chunks(Module, [exports]) of
	    {ok, {ModuleName, Exports}} ->
		{value, Flatten} = 
		    lists:keysearch(exports, 1, Exports),
		case lists:member({Fun, Arity}, element(2, Flatten)) of
		    false -> [];
		    true -> 
%%			?debug("Module ~p Name ~p",[Module, ModuleName],
%%			       get_modules_with_fun),
			[ModuleName]
		end;
	    {error, beam_lib, _Reason}->
		%% just skip files with errors no special handling
		[]
	end,
    get_modules_with_fun(ListOfFiles, Fun, Arity, Res ++ Result).


%%--------------------------------------------------------------------
%% @doc
%%    Starts server.
%% @end
%%-spec(start_link/3 :: (Transport :: atom(), Args :: list()) -> 
%%	     {ok, Pid :: pid()} | {error, Reason :: term()}).
start_link() ->
       start_link([]).
%%     start_link(?MODULE).

%% start_link(Name) ->
%%     gen_server:start_link({local, Name}, ?MODULE, {}, []).
start_link(Args) ->
    %% TODO add the possibility to configure name
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc
%%     Stops server.
%% @end
stop() ->
    stop(?MODULE).
-spec(stop/1 :: (Pid :: pid()) -> ok).
stop(Pid) ->
    (catch gen_server:call(Pid, stop)),
    ok.

%% @doc
%%    Returns the state of server.
%% @end
status() ->
    status(?MODULE).
-spec(status/1 :: (Pid :: atom() | pid()) -> 
	     {ok, Pid, #state{}} | {ok, not_running, Pid} 
		 | {error, Reason :: term()}). 
status(Pid)->
    try gen_server:call(Pid, status) of
	Result->Result
	catch
 	  _:_Reason -> {ok, not_running, Pid}
	end.

%%==================================================
%% gen_server callbacks
%%==================================================
-type(reason() :: term()).
-spec(init/1 :: (Args :: [term()]) -> {ok, #state{}} 
					  | {ok, #state{}, Timeout :: integer()}
					  | {ok, #state{}, hibernate}
					  | {stop, reason()} 
					  | ignore).
%%                               {reuseaddr, true},
init(Args) -> 
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @doc
%%  Handling call messages. Callback function that will be invoked by gen_server.
%% @end
-spec(handle_call/3 :: 
      (status, From :: pid(), #state{}) -> {reply, Reply :: term(), #state{}};
      (stop, From :: pid(), #state{}) -> {stop, normal, #state{}};
      (Request :: term(), From :: pid(), #state{}) -> 
	     {reply, {error, {unhandled_call, Request :: term(), From :: pid()}},
	      #state{}};
      (M :: term(), From :: pid(), #state{}) -> 
	     {reply, Reply :: term(), #state{}};
      (M :: term(), From :: pid(), #state{}) -> 
	     {reply, Reply :: term(), #state{}, Timeout :: integer()};
      (M :: term(), From :: pid(), #state{}) -> {noreply, #state{}};
      (M :: term(), From :: pid(), #state{}) -> 
	     {noreply, #state{}, Timeout :: integer()};
      (M :: term(), From :: pid(), #state{}) -> 
	     {stop, Reason :: term(), Reply :: term(), #state{}};
      (M :: term(), From :: pid(), #state{}) -> 
	     {stop, Reason :: term(), #state{}}).
%%--------------------------------------------------------------------

handle_call(status, _From, State) ->
    KVs = ?record_to_keyval(state, State),
    Reply={ok, self(), KVs},
    {reply, Reply, State};
handle_call(stop, _From, State) ->
    {stop, normal, State};

handle_call(Request, From, State) ->
    ?debug("Got unhandled call ~p from ~p.", [Request, From], handle_call),
    {reply, {error, {unhandled_call, Request, From}}, State}.

%%--------------------------------------------------------------------
%% @doc
%%  Handling cast messages. Callback function that will be invoked by gen_server.
%% @end
-spec(handle_cast/2 :: 
      (status, #state{}) -> {reply, Reply :: term(), #state{}};
      (Request :: term(), #state{}) -> 
	     {reply, {error, {unhandled_call, Request :: term(), From :: pid()}},
	      #state{}};
      (M :: term(), #state{}) -> {noreply, #state{}};
      (M :: term(), #state{}) -> {noreply, #state{}, Timeout :: integer()};
      (M :: term(), #state{}) -> {noreply, #state{}, hibernate};
      (M :: term(), #state{}) -> {stop, Reason :: term(), #state{}}).
%%--------------------------------------------------------------------

handle_cast(Message, State) ->
    ?debug("Got unhandled info message ~p.", [Message], handle_info),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%%     Handling all non call/cast messages. 
%%     Callback function that will be invoked by gen_server.
%% @end
%%--------------------------------------------------------------------
-spec(handle_info/2 :: 
      ({'EXIT', Pid :: pid(), normal}, State :: #state{}) -> {noreply, #state{}};
      (M :: term(), #state{}) -> {noreply, #state{}};
      (M :: term(), #state{}) -> {noreply, #state{}, Timeout :: integer()};
      (M :: term(), #state{}) -> {noreply, #state{}, hibernate};
      (M :: term(), #state{}) -> {stop, Reason :: term(), #state{}}).

handle_info(Message, State) ->
    ?debug("Got unhandled info message ~p.", [Message], handle_info),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%%    This function is called by a gen_server when it is about to
%%    terminate. It should be the opposite of Module:init/1 and do any necessary
%%    cleaning up. When it returns, the gen_server terminates with Reason.
%%    The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec(terminate/2 :: (Reason :: term(), #state{}) -> ok).
terminate(_Reason, #state{}) ->
    ok.

%%--------------------------------------------------------------------
%% @doc 
%%    Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec(code_change/3 :: (OldVsn :: term(), #state{}, Extra :: term()) -> 
	     {ok, #state{}}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%==================================================
%% Internal functions
%%==================================================


