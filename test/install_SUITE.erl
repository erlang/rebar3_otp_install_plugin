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
-module(install_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(FUNCTION_STRING,atom_to_list(?FUNCTION_NAME)).

suite() ->
    [{timetrap,{seconds,30}}].

init_per_suite(Config) ->
    LibDir = code:lib_dir(rebar3_otp_install_plugin),
    PluginRepo = filename:join(lists:takewhile(fun("_build") -> false;
                                                  (_) -> true
                                               end,
                                               filename:split(LibDir))),
    %% The following fakes a global rebar.config with the plugin specified
    State = rebar_state:new([plugin_spec(PluginRepo)]),
    [{plugin_repo,PluginRepo},{lib_dir,LibDir},{state,State}|Config].

end_per_suite(_Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    {ok,Cwd} = file:get_cwd(),
    PrivDir = filename:join(proplists:get_value(priv_dir,Config),TestCase),
    ok = file:make_dir(PrivDir),
    ok = file:set_cwd(PrivDir),
    [{cwd,Cwd},{priv_dir,PrivDir}|proplists:delete(priv_dir,Config)].

end_per_testcase(_TestCase, Config) ->
    Cwd = proplists:get_value(cwd,Config),
    ok = file:set_cwd(Cwd),
    ok.

all() -> 
    [given_app,
     given_app_local_repo,
     given_app_local_repo_escript,
     current_app,
     current_app_plugin_in_repo,
     deps,
     nodeps,
     no_app,
     illegal_opt
    ].

given_app(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    make_checkout_plugin(Config),
    State = proplists:get_value(state,Config),
    {ok,_} = rebar3:run(State,["otp","install","egd","--target",PrivDir]),
    [AppDir] = filelib:wildcard(filename:join([PrivDir,"erlang","lib","*"])),
    "egd-"++_ = filename:basename(AppDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","egd"])),
    ok.

given_app_local_repo(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    make_checkout_plugin(Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    RepoDir = make_app_repo(PrivDir,AppName),
    State = proplists:get_value(state,Config),
    {ok,_} = rebar3:run(State,["otp","install",AppName,"--repo",RepoDir,
                               "--target",PrivDir]),
    check_lib_dir([AppName],PrivDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    ok.

given_app_local_repo_escript(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    make_checkout_plugin(Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    RepoDir = make_app_repo(PrivDir,AppName),
    ok = escriptize(list_to_atom(AppName),RepoDir),
    State = proplists:get_value(state,Config),
    {ok,_} = rebar3:run(State,["otp","install",AppName,"--repo",RepoDir,
                               "--target",PrivDir]),
    check_lib_dir([AppName],PrivDir),
    [Bin] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    AppName = filename:basename(Bin),
    ok.

current_app(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    {ok,_} = rebar3:run(["new","app",AppName]),
    RepoDir = filename:join(PrivDir,AppName),
    ok = file:set_cwd(RepoDir),
    make_checkout_plugin(Config),
    {ok,RebarConfig} = file:consult("rebar.config"),
    State = rebar_state:new([{plugins,[rebar3_otp_install_plugin]}|RebarConfig]),
    {ok,_} = rebar3:run(State,["otp","install","--target",PrivDir]),
    check_lib_dir([AppName],PrivDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    ok.

current_app_plugin_in_repo(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    {ok,_} = rebar3:run(["new","app",AppName]),
    RepoDir = filename:join(PrivDir,AppName),
    add_plugin(RepoDir,proplists:get_value(plugin_repo,Config)),
    ok = file:set_cwd(RepoDir),
    make_checkout_plugin(Config),
    {ok,_} = rebar3:run(["otp","install","--target",PrivDir]),
    check_lib_dir([AppName],PrivDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    ok.

deps(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    make_checkout_plugin(Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    DepName = ?FUNCTION_STRING ++ "_dep",
    RepoDir = make_app_repo(PrivDir,AppName,[DepName]),
    _ = make_app_repo(PrivDir,DepName),

    State = proplists:get_value(state,Config),
    {ok,_} = rebar3:run(State,["otp","install",AppName,"--repo",RepoDir,
                              "--target",PrivDir]),
    check_lib_dir([AppName,DepName],PrivDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    ok.

nodeps(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    make_checkout_plugin(Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    DepName = ?FUNCTION_STRING ++ "_dep",
    RepoDir = make_app_repo(PrivDir,AppName,[DepName]),
    _ = make_app_repo(PrivDir,DepName),

    State = proplists:get_value(state,Config),
    {ok,_} = rebar3:run(State,["otp","install",AppName,"--repo",RepoDir,
                               "--target",PrivDir,"--nodeps"]),
    check_lib_dir([AppName],PrivDir),
    [] = filelib:wildcard(filename:join([PrivDir,"erlang","bin","*"])),
    ok.

no_app(Config) ->
    make_checkout_plugin(Config),
    State = proplists:get_value(state,Config),
    {error,{rebar3_otp_install_plugin_prv,no_app}} =
        rebar3:run(State,["otp","install"]),
    ok.

illegal_opt(Config) ->
    PrivDir = proplists:get_value(priv_dir,Config),
    AppName = ?FUNCTION_STRING ++ "_app",
    {ok,_} = rebar3:run(["new","app",AppName]),
    RepoDir = filename:join(PrivDir,AppName),
    ok = file:set_cwd(RepoDir),
    make_checkout_plugin(Config),
    State = proplists:get_value(state,Config),
    {error,{rebar3_otp_install_plugin_prv,{local,version}}} =
	rebar3:run(State,["otp","install","--version","1.0"]),
    {error,{rebar3_otp_install_plugin_prv,{local,tag}}} =
	rebar3:run(State,["otp","install","--tag","1.0"]),
    {error,{rebar3_otp_install_plugin_prv,{local,ref}}} =
	rebar3:run(State,["otp","install","--ref","eafea"]),
    {error,{rebar3_otp_install_plugin_prv,{local,branch}}} =
	rebar3:run(State,["otp","install","--branch","master"]),

    {error,Reason1} =
	rebar3:run(State,["otp","install","--illegal","opt"]),
    "Invalid option --illegal on task install" = lists:flatten(Reason1),
    {error,Reason2} =
	rebar3:run(State,["otp","install","--target"]),
    "Missing argument to option target" = lists:flatten(Reason2),

    ok.

%%%-----------------------------------------------------------------
%%% Internal
make_app_repo(Dir,Name) ->
    {ok,Cwd} = file:get_cwd(),
    {ok,_} = rebar3:run(["new","app",Name]),
    RepoDir = filename:join(Dir,Name),
    ok = file:set_cwd(RepoDir),
    os:cmd("git init"),
    os:cmd("git add src rebar.config"),
    os:cmd("git commit -m \"initial commit\""),
    ok = file:set_cwd(Cwd),
    RepoDir.

make_app_repo(Dir,Name,Deps) ->
    {ok,Cwd} = file:get_cwd(),
    RepoDir = make_app_repo(Dir,Name),
    ok = file:set_cwd(RepoDir),
    {ok,RebarConfig} = file:consult("rebar.config"),
    DepSpecs = [{list_to_atom(Dep),{git,filename:join(Dir,Dep),{branch,master}}}
		|| Dep <- Deps],
    RebarConfig1 = lists:keystore(deps,1,RebarConfig,{deps,DepSpecs}),
    RebarConfigStr = [io_lib:format("~p.~n",[C]) || C<-RebarConfig1],
    file:write_file("rebar.config",RebarConfigStr),
    os:cmd("git add rebar.config"),
    os:cmd("git commit -m \"Add deps\""),
    ok = file:set_cwd(Cwd),
    RepoDir.

add_plugin(RepoDir,PluginDir) ->
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(RepoDir),
    {ok,RebarConfig} = file:consult("rebar.config"),
    RebarConfig1 = lists:keystore(plugins,1,RebarConfig,plugin_spec(PluginDir)),
    RebarConfigStr = [io_lib:format("~p.~n",[C]) || C<-RebarConfig1],
    ok = file:write_file("rebar.config",RebarConfigStr),
    os:cmd("git add rebar.config"),
    os:cmd("git commit -m \"Add plugins\""),
    ok = file:set_cwd(Cwd).

plugin_spec(PluginDir) ->
    {plugins,
     [{list_to_atom(filename:basename(PluginDir)),
       {git,PluginDir,{branch,master}}}
     ]}.

escriptize(Name,RepoDir) ->
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(RepoDir),
    {ok,RebarConfig} = file:consult("rebar.config"),
    RebarConfig1 =
        case lists:keytake(provider_hooks,1,RebarConfig) of
            false ->
                Post = [{post, [{compile, {default,escriptize}}]}],
                [{provider_hooks,Post}|RebarConfig];
            {{value,{provider_hooks,PH}},RestConfig} ->
                ProviderHooks =
                    case lists:keytake(post,1,PH) of
                    false ->
                            [{post, [{compile, {default,escriptize}}]}|PH];
                        {{value,{post,P}},RestPH} ->
                            [{post, [{compile, {default,escriptize}}|P]}|RestPH]
                    end,
                [{provider_hooks,ProviderHooks}|RestConfig]
        end,
    RebarConfig2 =
        [{escript_incl_apps,[Name]},
         {escript_main_app, Name},
         {escript_name, Name} | RebarConfig1],
    RebarConfigStr = [io_lib:format("~p.~n",[C]) || C<-RebarConfig2],
    file:write_file("rebar.config",RebarConfigStr),
    os:cmd("git add rebar.config"),
    os:cmd("git commit -m \"Add escript\""),
    ok = file:set_cwd(Cwd).

make_checkout_plugin(Config) ->
    ok = file:make_dir("_checkouts"),
    ok = file:make_symlink(proplists:get_value(lib_dir,Config),
			   "_checkouts/rebar3_otp_install_plugin").

check_lib_dir(AppNames,TargetDir) ->
    NameVsns = lists:sort([N ++ "-0.1.0" || N <- AppNames]),
    ct:log("Expected Name-Vsn dirs: ~p~n",[NameVsns]),
    CheckDirs = filelib:wildcard(filename:join([TargetDir,"erlang","lib","*"])),
    NameVsns = lists:sort([filename:basename(D) || D <- CheckDirs]).
