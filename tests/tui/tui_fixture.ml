open! Core
open Bonsai_term
module App_recovery = Tmux_recovery_application.Recovery
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

let workspace =
  let sessions : Workspace.Session.t list =
    [ { id = "$1"; name = "development"; attached = true } ]
  in
  let windows : Workspace.Window.t list =
    [ { id = "@1"; name = "monitoring"; layout = "layout-a" } ]
  in
  let links : Workspace.Window_link.t list =
    [ { id = "$1/@1"; session_id = "$1"; window_id = "@1"; index = 0; active = true } ]
  in
  let panes : Workspace.Pane.t list =
    [ { id = "%1"
      ; window_id = "@1"
      ; index = 0
      ; active = true
      ; title = "btop"
      ; cwd = "/Users/demo"
      ; current_command = "btop"
      ; pid = Some 42
      ; tty = Some "/dev/ttys001"
      }
    ]
  in
  let server : Workspace.Server.t =
    { available = true; socket = None; version = Some "tmux test" }
  in
  Workspace.create ~source:Live ~server sessions windows links panes
  |> Result.map_error ~f:(String.concat ~sep:"; ")
  |> Result.ok_or_failwith
;;

let snapshot_id =
  Snapshot.Id.of_string "tmux_resurrect_20260720T213239.txt" |> Or_error.ok_exn
;;

let snapshots : Snapshot.catalog Or_error.t =
  Ok
    { directory = "/Users/demo/.local/share/tmux/resurrect"
    ; directory_exists = true
    ; snapshots =
        [ { id = snapshot_id
          ; created_at = Time_ns.epoch
          ; size_bytes = 4096L
          ; latest = true
          ; last_good = true
          ; validity = Valid
          ; warnings = []
          ; session_count = 1
          ; window_count = 1
          ; pane_count = 1
          ; manifest = false
          ; legacy = true
          }
        ]
    ; warnings = []
    }
;;

let services : Service.t Or_error.t =
  Ok
    { manager = Launchd
    ; ownership = Legacy
    ; periodic_save =
        { activation = Loaded
        ; schedule = Some "600 seconds"
        ; definition = Some "/Users/demo/Library/LaunchAgents/com.demo.tmux-save.plist"
        }
    ; login_restore =
        { activation = Loaded
        ; schedule = Some "at login"
        ; definition = Some "/Users/demo/Library/LaunchAgents/com.demo.tmux.plist"
        }
    ; binary_path = Some "/Users/demo/bin/tmux-resurrect-save-safe"
    ; binary_version = None
    ; last_result = Some "launchctl exit status 0"
    ; next_run = None
    ; conflicts = []
    ; warnings = [ "legacy tmux automation detected; tmux-recovery will not modify it" ]
    }
;;

let make_app ~snapshots ~services =
  let service = App_recovery.create ~socket_name:"tmux-recovery-golden-test" () in
  let capture_pane ~pane_id:_ =
    Effect.return
      (Ok
         [ "older output 01"
         ; "older output 02"
         ; "older output 03"
         ; "older output 04"
         ; "older output 05"
         ; "older output 06"
         ; "older output 07"
         ; "older output 08"
         ; "older output 09"
         ; "older output 10"
         ; "older output 11"
         ; "older output 12"
         ; "$ printf 'latest pane output\\n'"
         ; "\027[38;2;122;202;154mlatest btop output\027[0m"
         ])
  in
  fun ~dimensions graph ->
    Tui.app
      ~capture_pane
      ~service
      ~initial:workspace
      ~initial_snapshots:snapshots
      ~initial_services:services
      ~exit:(fun () -> Effect.Ignore)
      ~dimensions
      graph
;;

let app = make_app ~snapshots ~services

let empty_app =
  let snapshots =
    Ok
      { Snapshot.directory = "/Users/demo/.local/share/tmux/resurrect"
      ; directory_exists = true
      ; snapshots = []
      ; warnings = []
      }
  in
  let services =
    Ok
      { Service.manager = Launchd
      ; ownership = Absent
      ; periodic_save = Service.empty_component
      ; login_restore = Service.empty_component
      ; binary_path = None
      ; binary_version = None
      ; last_result = None
      ; next_run = None
      ; conflicts = []
      ; warnings = []
      }
  in
  make_app ~snapshots ~services
;;

let unavailable_app =
  make_app
    ~snapshots:(Or_error.error_string "fixture snapshot directory is unreadable")
    ~services:(Or_error.error_string "fixture service manager is unavailable")
;;
