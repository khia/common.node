-module(common.node.init).

-include("debug.hrl").
-include("utils.hrl").
-import(common.utils.lists, [errors/1]).
-import(common.node.code, [get_modules_with_fun/2]).
-import(common.db.db, [create_tables/2]).
-import(lists).

-export([init/1]).

init(Nodes) ->
    ?assert(common.cm.db:init(Nodes)),	
    Applications = applications(),
    ?debug("About to configure applications: ~p.", [Applications], init),
    case errors(init_applications(Nodes, Applications)) of
	[] -> ok;
	Applications_Errors -> 
	    ?error("Cannot init_applications: ~p.",[Applications_Errors],init),
	    {error, {cannot_init_applications, Applications_Errors}}
    end,
    Tables = tables(),
    ?debug("About to create tables: ~p.",[Tables], init),

    case errors(create_tables(Nodes, Tables)) of
	[] -> ok;
	Tables_Errors -> 
	    ?error("Cannot create_tables: ~p.",[Tables_Errors],init),
	    {error, {cannot_create_tables, Tables_Errors}}
    end.

tables() -> get_modules_with_fun(create_tables, 1).
applications() -> get_modules_with_fun(init_app, 1).

init_applications(Nodes, Applications) ->
    lists:foldl(
      fun(App, Res) ->
	      case App:init_app(Nodes) of
		  ok -> [{App, true}] ++ Res;
		  {atomic, ok} -> [{App, true}] ++ Res;
		  Error -> [{App, Error}] ++ Res
	      end
      end, [], Applications).
