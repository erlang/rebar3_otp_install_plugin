%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2017. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(rebar3_otp_install_plugin_prv).

-export([init/1, do/1, format_error/1]).

-define(NAMESPACE, otp).
-define(PROVIDER, install).
-define(FULL_NAME, atom_to_list(?NAMESPACE)++"_"++atom_to_list(?PROVIDER)).
-define(DEPS, [{default,compile}]).

-define(GIT_URL(App), "git@github.com:erlang/"++atom_to_list(App)++".git").
-define(REL_LIB_DIR, filename:join(["rel",?FULL_NAME,"lib"])).
-define(BIN_DIR,"bin").
-define(DEFAULT_USER_PREFIX,filename:join(os:getenv("HOME"),".local")).
-define(DEFAULT_USER_TARGET,filename:join(?DEFAULT_USER_PREFIX,"lib")).
-define(RELX_CONFIG,"otp_install_relx.config").

-define(ERROR(Reason), throw({error,{?MODULE,Reason}})).

-define(DEBUG, begin __DEBUG__=os:getenv("DEBUG"), __DEBUG__=/="" andalso __DEBUG__=/=false end).

-define(TMP_DIR,
	rebar_file_utils:system_tmpdir(["."++?FULL_NAME])).

-record(opts,{app,
	      repo,
	      version,
	      tag,
	      ref,
	      branch,
	      target=?DEFAULT_USER_TARGET,
	      include_deps=true}).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
            {name, ?PROVIDER},
            {module, ?MODULE},
	    {namespace, ?NAMESPACE},
            {bare, true},
            {deps, ?DEPS},
            {example, "rebar3 otp install xmerl --target=my-local-path"},
            {opts,
	     [{app,undefined,undefined,atom,help(app)},
	      {repo,$r,"repo",string,help(repo)},
	      {version,$v,"version",string,help(version)},
	      {tag,$t,"tag",string,help(tag)},
	      {ref,$r,"ref",string,help(ref)},
	      {branch,$b,"branch",string,help(branch)},
	      {target,$o,"target",string,help(target)},
	      {nodeps,undefined,"nodeps",undefined,help(nodeps)}]},
            {short_desc, "A rebar3 plugin for installing OTP applications"},
            {desc, "A rebar3 plugin for installing OTP applications"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

help(app) ->
    "The application to install. If not given, the application found in the current directory is installed.";
help(repo) ->
    "Git repository to fetch application from. Default is the official erlang/OTP repository for the given application.";
help(version) ->
    "Application version. Default is the latest from master branch.";
help(tag) ->
    "Git tag for application. Default is the latest from master branch.";
help(ref) ->
    "Git ref for application. Default is the latest from master branch.";
help(branch) ->
    "Git branch for application. Default is master.";
help(target) ->
    "Directory where the apps shall be installed. A subdirectory named erlang will be created under the given target directory. Default is "++?DEFAULT_USER_TARGET ++ ".";
help(nodeps) ->
    "Install only the primary application, no dependecies.".

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    try install(State,get_opts(State))
    catch throw:Error ->
	    Error
    end.

-spec format_error(any()) ->  iolist().
format_error(no_app) ->
    io_lib:format(
      "No application found.~n"
      "Please give application name or execute inside application project.~n"
      "Run \"rebar3 help otp install\" for more info.",[]);
format_error({local,Opt}) ->
    io_lib:format(
      "Option '~w' specified but no application.~n"
      "If installing application from current project, HEAD will be used.",[Opt]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

install(State,Opts=#opts{app=undefined}) ->
    case filelib:is_regular("rebar.config") of
	true ->
	    %% we're in a rebar project, let's try to install current app
	    check_no_version_opts(Opts),
	    rebar_api:info("Installing application from current project",[]),
	    local_install(State,Opts);
	false ->
	    ?ERROR(no_app)
    end;
install(State,Opts) ->
    {ok,StartDir} = file:get_cwd(),
    TmpDir = ?TMP_DIR,
    rebar_file_utils:reset_dir(TmpDir),
    ok = file:set_cwd(TmpDir),
    try do_install(Opts) of
        {ok,_} -> {ok,State};
        Error -> Error
    after
	file:set_cwd(StartDir),
	?DEBUG orelse rebar_file_utils:rm_rf(TmpDir)
    end.

do_install(Opts) ->
    Config = rebar_config(Opts),
    ok = file:write_file("rebar.config",
			 [io_lib:format("~p.~n",[C]) || C<- Config]),
    case rebar3:run(["compile"]) of
        {ok,State} ->
            local_install(State,Opts);
        Error ->
            Error
    end.

local_install(State,Opts) ->
    try do_local_install(State,Opts)
    after
	?DEBUG orelse file:delete(?RELX_CONFIG)
    end.

do_local_install(State,Opts) ->
    %% Find all project apps and deps and include in relx config
    AppNames = get_apps(State,Opts),
    rebar_api:info("Installing applications: ~p",[AppNames]),
    Config = relx_config(AppNames),
    ok = file:write_file(?RELX_CONFIG,[io_lib:format("~p.~n",[C]) || C<- Config]),
    State1 = silent_release(State),
    {TargetLib,TargetBin} = get_target_dirs(Opts#opts.target),
    ok = filelib:ensure_dir(filename:join(TargetLib,"*")),
    AppsWC = io_lib:format("~w-*",[list_to_tuple(AppNames)]),
    BuildDir = rebar_dir:base_dir(State1),
    Libs = filelib:wildcard(filename:join([BuildDir,?REL_LIB_DIR,AppsWC])),
    rebar_file_utils:cp_r(Libs,TargetLib),
    case filelib:wildcard(filename:join([BuildDir,?BIN_DIR,"*"])) of
        [] ->
            ok;
        Bins ->
            ok = filelib:ensure_dir(filename:join(TargetBin,"*")),
            rebar_file_utils:cp_r(Bins,TargetBin)
    end,
    check_erlang_code_path(TargetLib),
    check_bin_path(TargetBin),
    {ok,State1}.

silent_release(State) ->
    {release,Args} = rebar3:parse_args(["release","--config", ?RELX_CONFIG]),
    State1 = rebar_state:command_args(State, Args),
    L = rebar_log:get_level(),
    ?DEBUG orelse rebar_log:set_level(rebar_log:error_level()),
    try rebar_prv_release:do(State1) of
        {ok,State2} ->
            State2;
        Error ->
            throw(Error)
    after
        rebar_log:set_level(L)
    end.

get_opts(State) ->
    {RawOpts,_} = rebar_state:command_parsed_args(State),
    rebar_api:debug("RawOpts: ~p",[RawOpts]),
    get_opts(RawOpts,#opts{}).

get_opts([{app,App}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{app=App});
get_opts([{repo,Repo}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{repo=Repo});
get_opts([{version,Vsn}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{version=Vsn});
get_opts([{tag,Tag}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{tag=Tag});
get_opts([{ref,Ref}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{ref=Ref});
get_opts([{branch,Branch}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{branch=Branch});
get_opts([{target,Target}|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{target=Target});
get_opts([nodeps|RawOpts],Opts) ->
    get_opts(RawOpts,Opts#opts{include_deps=false});
get_opts(_,Opts) ->
    Opts.

check_no_version_opts(Opts = #opts{app=undefined}) ->
    Opts#opts.version=/=undefined andalso ?ERROR({local,version}),
    Opts#opts.tag=/=undefined andalso ?ERROR({local,tag}),
    Opts#opts.ref=/=undefined andalso ?ERROR({local,ref}),
    Opts#opts.branch=/=undefined andalso ?ERROR({local,branch}).

get_target_dirs(Target) ->
    ErlangDir = filename:join(Target,"erlang"),
    {filename:join(ErlangDir,"lib"),filename:join(ErlangDir,"bin")}.

get_apps(State,Opts) ->
    ProjectApps =
	case Opts#opts.app of
	    undefined -> app_names(rebar_state:project_apps(State));
	    App -> [App]
	end,
    Deps =
	if Opts#opts.include_deps ->
		app_names(rebar_state:all_deps(State)) -- ProjectApps;
	   true ->
		[]
	end,
    ProjectApps ++ Deps.

app_names(AppInfos) ->
    [binary_to_atom(rebar_app_info:name(AI),utf8) || AI <- AppInfos].

rebar_config(Opts) ->
    [{deps, [{Opts#opts.app,git(Opts)}]}].

relx_config(Apps) ->
    [{release, {list_to_atom(?FULL_NAME), "1.0"},
      [kernel,stdlib] ++ [{App,none}||App<-Apps]},
     {dev_mode, false},
     {include_erts, false},
     {system_libs, false},
     {extended_start_script, false}].

git(Opts) ->
    {git,repo(Opts),version(Opts)}.

repo(#opts{app=App,repo=undefined}) ->
    ?GIT_URL(App);
repo(#opts{repo=Repo}) ->
    Repo.

version(#opts{version=Vsn}) when Vsn=/=undefined ->
    {tag,Vsn};
version(#opts{tag=Tag}) when Tag=/=undefined ->
    {tag,Tag};
version(#opts{ref=Ref}) when Ref=/=undefined ->
    {ref,Ref};
version(#opts{branch=Branch}) when Branch=/=undefined ->
    {branch,Branch};
version(_) ->
    "".

check_erlang_code_path(Target) ->
    CodePath = code:get_path(),
    CodePathN = [normalize(P) || P <- CodePath],
    check_prefix(Target,CodePathN).

check_prefix(Prefix,[]) ->
    rebar_api:warn("You don't have libs under ~s in your code path",[Prefix]);
check_prefix(Prefix,[Dir|Dirs]) ->
    case lists:prefix(Prefix,Dir) of
	true -> ok;
	false -> check_prefix(Prefix,Dirs)
    end.

check_bin_path(BinDir) ->
    case file:list_dir(BinDir) of
	{ok,Bins} when Bins=/=[] ->
	    Path = string:tokens(os:getenv("PATH"),path_separator()),
	    PathN = [normalize(P) || P <- Path],
	    BinDirN = normalize(BinDir),
	    case lists:member(BinDirN,PathN) of
		true ->
		    ok;
		false ->
		    rebar_api:warn("You don't have ~s in your path",[BinDir])
	    end,
	    ok;
	_ ->
	    ok
    end.

path_separator() ->
    case os:type() of
	{win32,_} ->
	    ";";
	{unix,_} ->
	    ":"
    end.

normalize(Name) ->
    Components = filename:split(filename:absname(Name)),
    normalize(Components,[]).

normalize([],Acc) ->
    filename:join(lists:reverse(Acc));
normalize(["."|T],Acc) ->
    normalize(T,Acc);
normalize([".."|T],Acc) ->
    normalize(T,tl(Acc));
normalize([H|T],Acc) ->
    normalize(T,[H|Acc]).
