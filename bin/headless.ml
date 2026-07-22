open! Core

let command =
  Command.group ~summary:"Inspect, plan, and safely recover tmux workspaces" Cli.commands
;;

let () =
  Command_unix.run
    ~version:Cli.version
    ~build_info:"OxCaml 5.2 · native snapshot schema 2 · headless recovery build"
    command
;;
