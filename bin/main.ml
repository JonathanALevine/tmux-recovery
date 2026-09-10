open! Core

let cli_command =
  Command.group ~summary:"Inspect, plan, and safely recover tmux workspaces" Cli.commands
;;

let () =
  let argv = Sys.get_argv () in
  let command, arguments =
    match Array.to_list argv with
    | [ _ ]
      when Core_unix.isatty Core_unix.stdin
           && Core_unix.isatty Core_unix.stdout
           && Option.is_none (Sys.getenv "COMP_CWORD") -> Tui.command, None
    | [ program ] when Option.is_none (Sys.getenv "COMP_CWORD") ->
      cli_command, Some [ program; "help" ]
    | _ :: "--socket" :: _ -> Tui.command, None
    | [ _; prefix ]
      when Option.equal String.equal (Sys.getenv "COMP_CWORD") (Some "1")
           && String.is_prefix prefix ~prefix:"-"
           && String.is_prefix "--socket" ~prefix -> Tui.command, None
    | _ -> cli_command, None
  in
  Command_unix.run
    ~version:(Cli.version ^ "+built-" ^ Cli.build_time)
    ~build_info:"OxCaml 5.2 · native snapshot schema 2 · guarded recovery build"
    ?argv:arguments
    command
;;
