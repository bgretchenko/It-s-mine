-module(cache_server).

-behaviour(gen_server).

%% API.
-export ([start_link/1]).
%-export ([process_loop/1]).
-export ([stop/1]).
-export ([insert/2]).
-export ([lookup/1]).
-export ([lookup_by_date/2]).
-export ([interval_delete/1]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-record (time_to_live, {
						key,
						value,
						datetime
						}).

-record (state, {ttl}).

start_link(Opts) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).   

stop(Pid) ->
    Pid ! stop.

insert(Key, Value) ->
	gen_server:call(?MODULE, {insert, Key, Value}).

lookup(Key) ->
	SecondsNow = calendar:datetime_to_gregorian_seconds(erlang:localtime()),
%	SecondsLess = SecondsNow - 60,
	case ets:lookup(default, Key) of
			[] ->
				undefined;
			[#time_to_live{datetime = Seconds, value=Value}] when SecondsNow < Seconds ->
				Value;
			[#time_to_live{datetime = Seconds}] when SecondsNow >= Seconds ->
					ets:delete(default, Key),
					was_deleted
%			[#time_to_live{value=Value}] ->
%				Value
	end.

lookup_by_date(DateFrom, DateTo) ->
	SecondsFrom = calendar:datetime_to_gregorian_seconds(DateFrom),
	SecondsTo = calendar:datetime_to_gregorian_seconds(DateTo),
	case ets:select(default,[{{'_','$2','$3','$4'},[{'>=', '$4', SecondsFrom}, {'=<', '$4', SecondsTo}],[['$2', '$3']]}]) of
		[] ->
			undefined;
		[Data] ->
			Data;
		[DataH|DataT] ->
			{ok,[DataH,DataT]}
	end.

interval_delete([_Opts]) ->
	Key = ets:first(default),
	SecondsNow = calendar:datetime_to_gregorian_seconds(erlang:localtime()),
	case Key of
		[] ->
			undefined;
		'$end_of_table' ->
			undefined;
		Key ->
			case ets:lookup(default, Key) of
				[#time_to_live{datetime = Seconds}] when SecondsNow >= Seconds ->
					ets:delete(default, Key),
					Key1 = ets:first(default),
					interval_delete([Key1]);
				[#time_to_live{datetime = Seconds}] when SecondsNow < Seconds ->
					Key2 = ets:next(default, Key),
					interval_delete([Key2])
			end
	end.
	
%% gen_server.

init(Opts) ->
	Sec = proplists:get_value(ttl, Opts, 600),
	ets:new(default, [ordered_set,
					named_table,
					public,
					{keypos, #time_to_live.key}]),
    io:format("Starting cache_server:~p sec~n", [Sec]),
	timer:apply_interval(Sec*1000, ?MODULE, interval_delete, [Opts]),
	{ok, #state{ttl = Sec}}.

%sync
handle_call({insert, Key, Value}, _From, State) ->
	Sec = State#state.ttl,
	Localtime = calendar:datetime_to_gregorian_seconds(erlang:localtime()),
	Data = #time_to_live{key=Key, value=Value, datetime = Sec + Localtime},
	ets:insert(default, Data),
	{reply, ok, State}.

%async
handle_cast(_Msg, State) ->
	{noreply, State}.
%async
handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

