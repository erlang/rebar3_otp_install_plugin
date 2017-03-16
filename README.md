rebar3_otp_install_plugin
=====

A rebar3 plugin for installing OTP applications


Description
-----------

This plugin makes it possible to restore the OTP bundle as it looked
before OTP-20, i.e. the applications that have been moved out of the
OTP repository can be installed into `/usr/local/lib/erlang/lib/` or
`$HOME/.local/lib/erlang/lib` or any other suitable place where `erl`
can find them again.

The decoupled applications are proper `rebar3` applications, but since
they are used in legacy project, this plugin is provided to allow
continued use without converting the projects to using `rebar3` for
packaging.

The plugin is implemented in the `otp` namespace.


Build
-----

    $ rebar3 compile

Usage
-----
	rebar3 otp install [<app>] [-r <repo>] [-v <version>] [-t <tag>]
                          [-r <ref>] [-b <branch>] [-o <target>]
                          [--nodeps]

    <app>          The application to install. If not given, the application
                   found in the current directory is installed.
    -r, --repo     Git repository to fetch application from. Default is the
                   official erlang/OTP repository for the given application.
    -v, --version  Application version. Default is the latest from master
                   branch.
    -t, --tag      Git tag for application. Default is the latest from
                   master branch.
    -r, --ref      Git ref for application. Default is the latest from
                   master branch.
    -b, --branch   Git branch for application. Default is master.
    -o, --target   Directory where the apps shall be installed. A
                   subdirectory named erlang will be created under the given
                   target directory. Default is $HOME/.local/lib.
    --nodeps       Install only the primary application, no dependecies.


Example
-------

Add the plugin to your rebar config (typically your global config
$HOME/.config/rebar3/rebar.config):

    {plugins, [{rebar3_otp_install_plugin,
                {git, "git@github.com:erlang/rebar3_otp_install_plugin.git",
                 {tag, "0.1"}}}
              ]}.

Then just call your plugin directly in any directory:


    $ rebar3 otp install typer -v 0.9.13
      ===> Compiling rebar3_otp_install_plugin
      ===> Verifying dependencies...
      ===> Verifying dependencies...
      ===> Fetching typer ({git,"git@github.com:erlang/typer.git",
                                       {tag,"0.9.13"}})
      ===> Fetching rebar3_appup_plugin ({pkg,<<"rebar3_appup_plugin">>,
                                                 <<"2.2.0">>})
      ===> Downloaded package, caching at ....
      ===> Compiling rebar3_appup_plugin
      ===> Compiling rebar3_otpdoc_plugin
      ===> Compiling typer
      ===> Compiling typer.appup.src
      ===> Building escript...
      ===> Installing applications: [typer]


or inside a OTP application directory:

	$ rebar3 otp install
      ===> Verifying dependencies...
      ===> Compiling typer
      ===> Compiling typer.appup.src
      ===> Building escript...
      ===> Installing application from current project
      ===> Installing applications: [typer]

Make sure that you start your erlang node with additional paths to
installed libs and executables.
