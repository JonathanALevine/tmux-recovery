open! Core

let command =
  Command.group
    ~summary:"Inspect, plan, and safely recover tmux workspaces"
    (("ui", Tui.command) :: Cli.commands)
;;

let () =
  let argv = Sys.get_argv () in
  let run ?argv () =
    Command_unix.run
      ~version:Cli.version
      ~build_info:"OxCaml 5.2 · native snapshot schema 2 · guarded recovery build"
      ?argv
      command
  in
  if Array.length argv = 1 && Core_unix.isatty Core_unix.stdin
  then run ~argv:[ argv.(0); "ui" ] ()
  else run ()
;;
