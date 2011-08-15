-module(common.node.node).

-import(init).
-import(erl_epmd).
-export([role/0, application/0, boot_server/0, attach/1, attach/2, local_dir/0]).
role() ->
    case init:get_argument(id) of
	error -> 
	    case init:get_argument(boot) of
		error -> unknown;
		_Boot_Server -> boot_server
	    end;
	_Id -> boot_client
    end.

%% MAYBE rename it to PRODUCT
application() ->
    case init:get_argument(id) of
	error -> init:get_argument(boot); %% boot_server 
	{ok, [[Id]]} -> Id %% boot_client
    end.
    
boot_server() ->
    case init:get_argument(boot_node) of
	error -> node(); %% boot_server
	{ok, [[Server]]} -> list_to_atom(Server) %% boot_client
    end.


attach(Node) ->
    attach(Node, 4369).

attach(Node, Port) ->
    EPMD = net_kernel:epmd_module(),
    EPMD:register_node(Node, Port).

local_dir() -> %% FIXME
    case init:get_argument(local) of
	error -> "local"; 
	{ok, [[Local]]} -> Local
    end.

    
