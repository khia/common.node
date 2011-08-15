-module(common.node.boot_server).

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
-import(io_lib).
-import(lists).
-import(erlang).
-import(net_kernel).
-import(gen_server).
-import(random).
%% modules that we need for send_modules/1 and send_modules/2
%%-import(rpc).
%%-import(common.db.db).
%%-import(code).

%%--------------------------------------------------------------------
%% API

%% Public API
-export([
	 get_name/1, register/3, register/4, create_cookie/0,
	 start/2]).

%% Server Control
-export([stop/0, stop/1, start_link/0, start_link/1, status/0, status/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, 
	 handle_info/2,
	 terminate/2, code_change/3]).

-type(now() :: {Mega :: integer(), Sec :: integer(), Micro :: integer()}).
-record(node, {id :: string(), 
	       idx :: integer(), 
	       host :: atom(), 
	       value :: atom(),
	       cookie :: string(),
	       ts :: now()}).

-record(state, {nodes = [] :: [#node{}]}).

-define(timeout, 1000).

register(App, Host, From) ->
    register(?MODULE, App, Host, From).

register(Pid, App, Host, From) ->
    gen_server:call(Pid, {register, App, Host, From}).


%% Application callback
%% FIXME
start(_Mode, _Args) ->
    start_link().

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
    ?debug("About to init boot_server on ~p with cookie ~p.",
	   [node(), ?default_client_cookie], init),
    erlang:set_cookie(node(), ?default_client_cookie),
    {ok, #state{}}.
    %%{stop, {error, {cannot_load_xrc, XRC_File}}}


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

handle_call({register, App, Host, From}, _From, State) ->
    {Reply, New_State} = handle_register(App, Host, From, State),
    {reply, Reply, New_State};

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
handle_register(App, Host, From, #state{nodes = Hosts} = State) 
  when is_list(App), is_list(Host) ->
    Host_Atom = list_to_atom(Host),
    Idx = find_last(App, Host_Atom, Hosts) + 1,
    Val = list_to_atom(App ++ lists:flatten(io_lib:format("~4.10.0B",[Idx])) 
			 ++ "@" ++ Host),
    Cookie = create_cookie(),
    Node = #node{id = App, idx = Idx, host = Host_Atom, 
		 value = Val, cookie = Cookie, ts = now()},
    erlang:set_cookie(Val, Cookie),
%%    send_modules(Val),
    erlang:disconnect_node(From),
    {{Val, Cookie}, State#state{nodes = [Node] ++ Hosts}}.

get_name(HostName) ->
    list_to_atom("client" ++ lists:flatten(io_lib:format("~p",[1])) ++ "@" 
		 ++ HostName).
%%    'client1@liveos-laptop'.

create_cookie() -> list_to_atom(random_list($A, $Z, 16)).

random_list(Min, Max, Len) ->
    random_list(Min, Max - Min, Len, []).
random_list(_Min, _Max, 1, Res) -> Res;
random_list(Min, Max, Len, Res) ->
    random_list(Min, Max, Len - 1, [Min + random:uniform(Max)] ++ Res).


find_last(App, Host, Hosts) ->
    find_last(Hosts, App, Host, []).

find_last([], _App, _Host, []) -> 0;
find_last([], _App, _Host, Res) -> lists:max(Res);
find_last([#node{id = App, host = Host, idx = Idx} | Rest], App, Host, Res) ->
    find_last(Rest, App, Host, [Idx] ++ Res);
find_last([_H | Rest], App, Host, Res) -> find_last(Rest, App, Host, Res).
    
%% send_modules(Node) ->
%%     Tables = db:local_tables(),
%%     [send_modules(Node, M) || M <- Tables, code:which(M) =/= non_existing].

%% send_modules(Node, Module) ->
%%     ?debug("About to send_module ~p to ~p",[Module, Node],send_modules),
%%     {Module, Binary, Filename} = code:get_object_code(Module),
%%     rpc:call(Node, code, load_binary, [Module, Filename, Binary]).

