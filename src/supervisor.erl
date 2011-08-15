%% PDU
-module(common.node.supervisor).

-behaviour(gen_server). 


%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("debug.hrl").
-include("utils.hrl").

%%--------------------------------------------------------------------
%% Import libraries
%%--------------------------------------------------------------------
%%-import(lists).
%%-import(proplists).
-import(gen_server).
%%-import(timer).

-define(RECONNECT_TIMEOUT, 5000).  %% 5 sec

%%--------------------------------------------------------------------
%% API

%% Public API
-export([]).

%% Server Control
-export([stop/1, start_link/2, start_link/3, status/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, 
	 handle_info/2,
	 terminate/2, code_change/3]).

%% Test functions
-export([test/1]).

-type(pid_or_name() :: pid() | atom()). 
-type(ets() :: term()).
-record(state, {name, 
		parent :: pid_or_name(), 
		role :: worker | supervisor, 
		children :: ets(), 
		strategy :: one_for_all | one_for_one 
		            | rest_for_one %% hard to implement with ets
                            | die_for_any | die_for_master,
		intensity :: integer(),
		period :: integer(),
		restarts = [] :: list(), 
		module :: atom(), 
		args :: term()}).
-record(child, {
	  id :: term(),
	  pid = undefined,  % pid is undefined when child is not running
	  mfa :: {M :: atom(), F :: atom(), A :: term()},
	  restart_type :: permanent | transient | temporary,
%% 	  start_timeout = 0 :: integer(),
	  intensity :: integer(), %% TODO
	  period :: integer(),    %% TODO
	  shutdown :: brutal_kill | integer() | infinity,
	  role :: worker | supervisor | master,
	  modules = []}).

%% Send message to cause a new connector to be created
create(ClientPid, Socket, Handler) ->
    gen_server:cast(ClientPid, {create, Socket, Handler}).

%%--------------------------------------------------------------------
%% @doc
%%    Starts server.
%% @end
-spec(start_link/2 :: (Module :: atom(), Args :: term()) ->
	    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Module, Args) -> 
    gen_server:start_link(Module, {self, Module, Args, self()}, []).
-spec(start_link/3 :: (Name :: {local, Name} | {global, Name}, 
		       Module :: atom(), Args :: term()) ->
	     {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Module, Args) -> 
    gen_server:start_link(Name, Module, {Name, Module, Args, self()}, []).

%% @doc
%%     Stops server.
%% @end
-spec(stop/1 :: (Pid :: pid()) -> ok).
stop(Pid) ->
    try gen_server:call(Pid, stop) of
	{Id, {parent, Parent}} -> supervisor:terminate_child(Parent, Id)
    catch _:_ -> ok
    end.

%% @doc
%%    Returns the state of server.
%% @end
-spec(status/1 :: (Pid :: atom() | pid()) -> 
	     {ok, Pid, #state{}} | {ok, not_running, Pid} 
		 | {error, Reason :: term()}). 
status(Pid) ->
    try gen_server:call(Pid, status) of
	Result->Result
	catch
 	  _:_Reason -> {ok, not_running, Pid}
	end.

-type(child() :: term()). %% TODO
-spec(create_child/2 :: (SupRef :: pid_or_name(), ChildSpec :: child()) ->
	    ok | {error, term()}).
create_child(SupRef, ChildSpec) ->
    gen_server:call(SupRef, {create_child, ChildSpec}, infinity).

-spec(start_child/2 :: (SupRef :: pid_or_name(), Id :: term()) ->
	     {ok, Child :: pid()} | {ok, Child :: pid(), Info :: term()} 
		 | {error, term()}).
start_child(SupRef, Id) ->
    gen_server:call(SupRef, {start_child, Id}, infinity).
-spec(terminate_child/2 :: (SupRef :: pid_or_name(), Id :: term()) ->
	    ok | {error, term()}).
terminate_child(SupRef, Id) ->
    gen_server:call(SupRef, {terminate_child, Id}, infinity).
-spec(restart_child/2 :: (SupRef :: pid_or_name(), Id :: term()) ->
	    {ok, Child :: pid()} | {ok, Child :: pid(), Info :: term()} 
		 | {error, term()}).
restart_child(SupRef, Id) ->
    gen_server:call(SupRef, {restart_child, Id}, infinity).
-spec(delete_child/2 :: (SupRef :: pid_or_name(), Id :: term()) ->
	    ok | {error, term()}).
delete_child(SupRef, Id) ->
    gen_server:call(SupRef, {delete_child, Id}, infinity).
-spec(which_children/1 :: (SupRef :: pid_or_name()) -> 
	     [{Id :: term(), Child :: pid(), Type :: atom(), Modules :: list()}]).
which_children(SupRef) -> gen_server:call(SupRef, which_children, infinity).
-spec(which_parent/1 :: (SupRef :: pid_or_name()) -> 
	     {ok, Pid_Or_Name :: pid_or_name()} | {error, term()}).
which_parent(SupRef) -> gen_server:call(SupRef, which_parent, infinity).

-spec(check_childspecs/1 :: (ChildSpecs :: [child()]) -> ok | {error, term()}).
check_childspecs(ChildSpecs) -> check_childspecs(ChildSpecs, ok).
check_childspecs([], ok) -> ok;
check_childspecs(ChildSpecs, {error, _Reason} = Error) -> Error;
check_childspecs([Spec | Rest], ok) ->
    Res = try check_childspec(Spec) of
	      ok -> ok;
	      Error -> Error
	  catch _:Reason -> {error, Reason}
		    end,
    check_childspecs(Rest, Res).



%%==================================================
%% gen_server callbacks
%%==================================================

%%--------------------------------------------------------------------
%% @doc
%%    Initiates the server. Callback function that will be invoked by gen_server.
%% @end
%%--------------------------------------------------------------------
-type(reason() :: term()).
-spec(init/1 :: (Args :: term()) -> {ok, #state{}} 
					| {ok, #state{}, Timeout :: integer()}
					| {ok, #state{}, hibernate}
					| {stop, reason()} 
					| ignore).
init({SupName, Mod, Args, Parent}) -> 
    process_flag(trap_exit, true),
    case Mod:init(Args) of
	{ok, {SupFlags, StartSpec}} -> 
	    case init_state(SupName, SupFlags, Mod, Args, Parent) of
		{ok, State} -> init_children(State, StartSpec);
		Error -> {stop, {supervisor_data, Error}}
	    end;
	ignore -> ignore;
	Error -> {stop, {bad_return, {Mod, init, Error}}}
    end.

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
handle_call(stop, _From, 
	    #state{name = Id, role = worker, parent = Parent} = State) ->
    {reply, {Id, {parent, Parent}}, State};
handle_call(stop, _From, State) ->
    {stop, normal, State};

handle_call({create_child, ChildSpec}, _From, #state{children = Table} = State) ->
    Reply = try init_child(ChildSpec) of
		#child{} = Child ->
		    ets:insert(Table, Child),
		    ok;
		Error -> Error
	    catch _:Reason -> {error, Reason}
		      end,
    {reply, Reply, State};
handle_call({start_child, Id}, _From, State)  -> 
    Reply = handle_start_child(Id, State),
    {reply, Reply, State};
handle_call({terminate_child, Id}, _From, State)  -> 
    Reply = handle_terminate_child(Id, State),
    {reply, Reply, State};
handle_call({restart_child, Id}, _From, State)  -> 
    Reply = handle_restart_child(Id, State),
    {reply, Reply, State};
handle_call({delete_child, Id}, _From, State)  -> 
    Reply = handle_delete_child(Id, State),
    {reply, Reply, State};
handle_call(which_children, _From, State)  -> 
    Reply = handle_which_children(State),
    {reply, Reply, State};
handle_call(which_parent, _From, #state{parent = Parent} = State) -> 
    {reply, {ok, Parent}, State};

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

handle_info({'EXIT', Pid, Reason}, State) -> %% Take care of terminated children.
    case restart_child(Pid, Reason, State) of
	{ok, State1} -> {noreply, State1};
	{shutdown, State1} -> {stop, shutdown, State1}
    end;

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
terminate(_Reason, State) ->
    ok.

%%--------------------------------------------------------------------
%% @doc 
%%    Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec(code_change/3 :: (OldVsn :: term(), #state{}, Extra :: term()) -> 
	     {ok, #state{}}).
code_change(_OldVsn, State, _Extra) -> %% FIXME
    {ok, State}.


init_state(SupName, SupFlags, Mod, Args, Parent) ->
    check_flags(SupFlags),
    {Strategy, Intensity, Period, Role} = SupFlags,
    {ok, #state{
       name = name(SupName),
       parent = parent(Parent),
       strategy = Strategy,
       intensity = Intensity, period = Period,
       role = Role,
       children = ets:new(child, [{keypos, 2}, private, set]),
       module = Mod, 
       args = Args
      }}.

check_flags({Strategy, Intensity, Period, Role}) ->
    validStrategy(Strategy),
    validIntensity(Intensity),
    validPeriod(Period),
    validSupRole(Role),
    ok.
    
init_children(State, Children) -> init_children(State, Children, []).
init_children(State, [], []) -> {ok, State};
init_children(#state{children = Table} = State, [], Errors) -> {stop, Errors};
init_children(#state{children = Table} = State, [Spec | Rest], Errors0) -> 
    Child = init_child(Spec),
    Error = case handle_start_child(Child, State) of
		ok -> [];
		Reason -> [Reason]
	    end,
    init_children(State, Rest, Error ++ Errors0).

init_child({Id, Func, Restart_Type, 
	    Timeout, Intensity, Period, Shutdown, Role, Mods} = Spec) ->    
    check_childspec(Spec),
    #child{id = Id, mfa = Func, 
	   restart_type = Restart_Type,
%%	   start_timeout = Timeout,
	   intensity = Intensity, period = Period,
	   shutdown = Shutdown,
	   role = Role,
	   modules = Mods};

init_child(What) -> {invalid_child_spec, What}.

check_childspec({Id, Func, Restart_Type, 
		 Timeout, Intensity, Period, Shutdown, Role, Mods}) ->    
    validFunc(Func),
    validRestart(Restart_Type),
%%    validTimeout(Timeout),
    validIntensity(Intensity),
    validPeriod(Period),
    validShatdown(Shutdown),
    validChildRole(Role),
    validModules(Mods),
    ok.

report_progress(Child, #state{name = Name, module = Module} = State) ->
    Progress = [{supervisor, Name}, 
		{started, ?record_to_keyval(child, Child)}],
    try Module:report_progress(Progress) of
	_Any -> ok
    catch _:_ -> error_logger:info_report(progress, Progress)
	     end.

report_error(Error, Reason, Child, 
	     #state{name = Name, module = Module} = State) ->
    ErrorMsg = [{supervisor, Name},
		{errorContext, Error},
		{reason, Reason},
		{offender, ?record_to_keyval(child, Child)}],
    try Module:report_error(ErrorMsg) of
	_Any -> ok
    catch _:_ -> error_logger:error_report(supervisor_report, ErrorMsg)
	     end.

validFunc({Module, Function, Args}) 
  when is_atom(Module), is_atom(Function), is_list(Args) -> true;
validFunc(Function) when is_function(Function) -> true;
validFunc(What) -> throw({invalid_function, What}).
    
validRestart(permanent) -> true;
validRestart(transient) -> true;
validRestart(temporary) -> true;
validRestart(What) -> throw({invalid_restart, What}).

%%    validTimeout(Timeout),

validIntensity(Intensity) when is_integer(Intensity) 
				 andalso Intensity >= 0 -> true;
validIntensity(What) -> throw({invalid_intensity, What}).

validPeriod(Period) when is_integer(Period) andalso Period > 0 -> true;
validPeriod(What) -> throw({invalid_period, What}).

validShatdown(brutal_kill) -> true;
validShatdown(infinity) -> true;
validShatdown(Shutdown) when is_integer(Shutdown) andalso Shutdown > 0 -> true;
validShatdown(What) ->  throw({invalid_shutdown, What}).

validSupRole(worker) -> true;
validSupRole(supervisor) -> true;
validSupRole(master) -> true;
validSupRole(What) -> throw({invalid_role, What}).

validModules(Modules) when is_list(Modules) -> true;
validModules(What) -> throw({invalid_modules, What}).

parent(Parent) ->
    case process_info(Parent, registered_name) of
	{registered_name,Name} -> Name;
	undefined -> Parent
    end.

name(self) -> {self, self()};
name(Name) -> Name.

validStrategy(simple_one_for_one) -> true;
validStrategy(one_for_one)        -> true;
validStrategy(one_for_all)        -> true;
validStrategy(rest_for_one)       -> true;
validStrategy(die_for_any)        -> true;
validStrategy(die_for_master)     -> true;
validStrategy(What)               -> throw({invalid_strategy, What}).

validChildRole(worker)     -> true;
validChildRole(supervisor) -> true;
validChildRole(What)       -> throw({invalid_role, What}).


-define(match_spec(Name, KeyVal),
	lists:to_record(Name, KeyVal, record_info(fields, Name), '_')).
handle_start_child(Id, #state{children = Table} = State) ->
    case ets:lookup(Table, Id) of
	[] -> {error, {no_such_child, Id}};
	[Child] -> handle_start_child(Child, State)
    end;	    
handle_start_child(#child{mfa = {M, F, A}} = Child, 
		   #state{children = Table} = State) ->
    try M:F(A) of
	{ok, Pid} when is_pid(Pid) ->
	    NChild = Child#child{pid = Pid},
	    report_progress(NChild, State),
	    ets:insert(Table, NChild),
	    {ok, Pid};
	{ok, Pid, Extra} when is_pid(Pid) ->
	    NChild = Child#child{pid = Pid},
	    report_progress(NChild, State),
	    ets:insert(Table, NChild),
	    {ok, Pid, Extra};
	ignore -> {ok, undefined};
	{error, _Reason} = Error -> Error;
	What -> {error, What}
    catch _:Reason -> {error, Reason}
	     end.

handle_terminate_child(Id, #state{children = Table} = State) ->
    case ets:lookup(Table, Id) of
	[] -> {error, {no_such_child, Id}};
	[Child] -> handle_terminate_child(Child, State)
    end; 
handle_terminate_child(#child{pid = undefined} = Child, _State) -> Child;
handle_terminate_child(#child{pid = Pid, shutdown = Shutdown} = Child, 
		       #state{children = Table} = State) ->
    case shutdown(Pid, Shutdown) of
	ok -> ok;
	{error, Reason} -> report_error(shutdown_error, Reason, Child, State)
    end,
    ets:insert(Table, Child#child{pid = undefined}).

handle_restart_child(Id, #state{children = Table} = State) ->
    case ets:lookup(Table, Id) of
	[] -> {error, {no_such_child, Id}};
	[Child] -> handle_restart_child(Child, State)
    end;
handle_restart_child(Child, State) ->
    handle_terminate_child(Child, State),
    handle_start_child(Child#child{pid = undefined}, State).

handle_delete_child(Id, #state{children = Table} = State) ->
    ets:delete(Table, Id),
    ok.

handle_which_children(#state{children = Table} = State) ->
    Children = ets:tab2list(Table),
    [{Child#child.id, Child#child.pid, Child#child.role, Child#child.modules} 
     || Child <- Children].

-spec(restart_child/3 :: (Pid :: pid(), Reason :: term(), State :: #state{}) ->
	    {ok, State} | {shutdown, State}).
restart_child(Pid, Reason, #state{children = Table} = State) ->
    Match_Spec = ?match_spec(child, [{pid, Pid}]),
    case ets:match_object(Table, Match_Spec) of
	[] -> {shutdown, State};
	[Child] -> do_restart(Child#child.restart_type, Reason, Child, State)
    end.
    
do_restart(permanent, Reason, Child, State) ->
    report_error(child_terminated, Reason, Child, State),
    restart(Child, State);
do_restart(_, normal, #child{id = Id}, #state{children = Table} = State) ->
    ets:delete(Table, Id),
    {ok, State};
do_restart(_, shutdown, #child{id = Id}, #state{children = Table} = State) ->
    ets:delete(Table, Id),
    {ok, State};
do_restart(transient, Reason, Child, State) ->
    report_error(child_terminated, Reason, Child, State),
    restart(Child, State);
do_restart(temporary, Reason, #child{id = Id} = Child, 
	   #state{children = Table} = State) ->
    report_error(child_terminated, Reason, Child, State),
    ets:delete(Table, Id),
    {ok, State}.

restart(#child{id = Id} = Child, #state{children = Table} = State) ->
    case add_restart(State) of
	{ok, NState} -> 
	    restart(NState#state.strategy, Child, NState);
	{terminate, NState} ->
	    report_error(shutdown, reached_max_restart_intensity, Child, State),
	    {shutdown, ets:delete(Table, Id)}
    end.

restart(one_for_one, Child, State) ->
    case handle_start_child(Child#child{pid = undefined}, State) of
	{error, Reason} ->
	    report_error(start_error, Reason, Child, State),
	    restart(Child, State);
	_Any -> {ok, State}
    end;

restart(one_for_all, Child, #state{children = Table} = State) ->
    Children = ets:tab2list(Table),
    terminate_children(Children, State),
    start_children(Children, State).
    
terminate_children(Children, State) -> %% FIXME
    [handle_terminate_child(Child, State) || Child <- Children].

start_children(Children, State) -> 
    start_children(Children, State, ok).
start_children([], State, ok) -> ok;
start_children([], State, Res) -> Res;
start_children([Child | Rest], State, _Res) ->
    Res = case handle_start_child(Child#child{pid = undefined}, State) of
	      {error, Reason} -> restart(Child, State);
	      _Any -> {ok, State}
	  end,
    start_children(Rest, State, Res).
	

%%% copy/paste from otp supervisor
%%-----------------------------------------------------------------
%% Shutdowns a child. We must check the EXIT value 
%% of the child, because it might have died with another reason than
%% the wanted. In that case we want to report the error. We put a 
%% monitor on the child an check for the 'DOWN' message instead of 
%% checking for the 'EXIT' message, because if we check the 'EXIT' 
%% message a "naughty" child, who does unlink(Sup), could hang the 
%% supervisor. 
%% Returns: ok | {error, OtherReason}  (this should be reported)
%%-----------------------------------------------------------------
shutdown(Pid, brutal_kill) ->
  
    case monitor_child(Pid) of
	ok ->
	    exit(Pid, kill),
	    receive
		{'DOWN', _MRef, process, Pid, killed} ->
		    ok;
		{'DOWN', _MRef, process, Pid, OtherReason} ->
		    {error, OtherReason}
	    end;
	{error, Reason} ->      
	    {error, Reason}
    end;

shutdown(Pid, Time) ->
    
    case monitor_child(Pid) of
	ok ->
	    exit(Pid, shutdown), %% Try to shutdown gracefully
	    receive 
		{'DOWN', _MRef, process, Pid, shutdown} ->
		    ok;
		{'DOWN', _MRef, process, Pid, OtherReason} ->
		    {error, OtherReason}
	    after Time ->
		    exit(Pid, kill),  %% Force termination.
		    receive
			{'DOWN', _MRef, process, Pid, OtherReason} ->
			    {error, OtherReason}
		    end
	    end;
	{error, Reason} ->      
	    {error, Reason}
    end.

%% Help function to shutdown/2 switches from link to monitor approach
monitor_child(Pid) ->
    
    %% Do the monitor operation first so that if the child dies 
    %% before the monitoring is done causing a 'DOWN'-message with
    %% reason noproc, we will get the real reason in the 'EXIT'-message
    %% unless a naughty child has already done unlink...
    erlang:monitor(process, Pid),
    unlink(Pid),

    receive
	%% If the child dies before the unlik we must empty
	%% the mail-box of the 'EXIT'-message and the 'DOWN'-message.
	{'EXIT', Pid, Reason} -> 
	    receive 
		{'DOWN', _, process, Pid, _} ->
		    {error, Reason}
	    end
    after 0 -> 
	    %% If a naughty child did unlink and the child dies before
	    %% monitor the result will be that shutdown/2 receives a 
	    %% 'DOWN'-message with reason noproc.
	    %% If the child should die after the unlink there
	    %% will be a 'DOWN'-message with a correct reason
	    %% that will be handled in shutdown/2. 
	    ok   
    end.
%%% ------------------------------------------------------
%%% Add a new restart and calculate if the max restart
%%% intensity has been reached (in that case the supervisor
%%% shall terminate).
%%% All restarts accured inside the period amount of seconds
%%% are kept in the #state.restarts list.
%%% Returns: {ok, State'} | {terminate, State'}
%%% ------------------------------------------------------

add_restart(State) ->  
    I = State#state.intensity,
    P = State#state.period,
    R = State#state.restarts,
    Now = erlang:now(),
    R1 = add_restart([Now|R], Now, P),
    State1 = State#state{restarts = R1},
    case length(R1) of
	CurI when CurI  =< I ->
	    {ok, State1};
	_ ->
	    {terminate, State1}
    end.

add_restart([R|Restarts], Now, Period) ->
    case inPeriod(R, Now, Period) of
	true ->
	    [R|add_restart(Restarts, Now, Period)];
	_ ->
	    []
    end;
add_restart([], _, _) ->
    [].

inPeriod(Time, Now, Period) ->
    case difference(Time, Now) of
	T when T > Period ->
	    false;
	_ ->
	    true
    end.

%%
%% Time = {MegaSecs, Secs, MicroSecs} (NOTE: MicroSecs is ignored)
%% Calculate the time elapsed in seconds between two timestamps.
%% If MegaSecs is equal just subtract Secs.
%% Else calculate the Mega difference and add the Secs difference,
%% note that Secs difference can be negative, e.g.
%%      {827, 999999, 676} diff {828, 1, 653753} == > 2 secs.
%%
difference({TimeM, TimeS, _}, {CurM, CurS, _}) when CurM > TimeM ->
    ((CurM - TimeM) * 1000000) + (CurS - TimeS);
difference({_, TimeS, _}, {_, CurS, _}) ->
    CurS - TimeS.

%%% End of copy/paste

    
%%handle_session_termination(Session_Sup, #state{sessions = Sessions} = State) ->
%    Ext = ?match_spec(ext, [{sup, Session_Sup}]),
%    Match_Spec = ?match_spec(session, [{ext, Ext}]),
%    Id = case ets:match_object(Sessions, Match_Spec) of
%	     [] -> unknown;
%	     [Session] -> 
%		 ets:insert(Sessions, Session#session{status = stopped}),
%		 client:connect(),
%		 Session#session.id
%	 end,
%    {ok, Id}.    

test(_) ->
    unknown.
