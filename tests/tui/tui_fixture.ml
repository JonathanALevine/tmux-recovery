open! Core
open Bonsai_term
module App_recovery = Tmux_recovery_application.Recovery
module Recovery = Tmux_recovery_domain.Recovery
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

let legacy_snapshot_id =
  Snapshot.Id.of_string "tmux_resurrect_20260720T213239.txt" |> Or_error.ok_exn
;;

let native_snapshot_id =
  Snapshot.Id.of_string "tmux_recovery_1784597559000000000_0123abcd.snapshot"
  |> Or_error.ok_exn
;;

let snapshots : Snapshot.catalog Or_error.t =
  Ok
    { directory = "/Users/demo/.local/share/tmux-recovery/snapshots"
    ; directory_exists = true
    ; snapshots =
        [ { id = native_snapshot_id
          ; created_at = Time_ns.epoch
          ; size_bytes = 8192L
          ; latest = true
          ; last_good = true
          ; validity = Valid
          ; warnings = []
          ; session_count = 1
          ; window_count = 1
          ; pane_count = 1
          ; manifest = true
          ; legacy = false
          }
        ; { id = legacy_snapshot_id
          ; created_at = Time_ns.epoch
          ; size_bytes = 4096L
          ; latest = false
          ; last_good = false
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
    ; ownership = Managed
    ; periodic_save =
        { activation = Loaded
        ; schedule = Some "600 seconds"
        ; definition = Some "/Users/demo/Library/LaunchAgents/com.demo.tmux-save.plist"
        ; command = Some "tmux-recovery snapshot --trigger timer --quiet"
        }
    ; login_restore =
        { activation = Loaded
        ; schedule = Some "at login"
        ; definition = Some "/Users/demo/Library/LaunchAgents/com.demo.tmux.plist"
        ; command = Some "tmux-recovery restore --approve --if-empty --quiet"
        }
    ; binary_path =
        Some "/Users/demo/.local/share/tmux-recovery/bin/current/tmux-recovery"
    ; binary_version = Some "0.3.0-dev.12"
    ; last_result = Some "launchctl exit status 0"
    ; next_run =
        Some "2026-07-21 01:42:39.000000000Z · estimated from the last timer save"
    ; last_restore =
        Some
          "2026-07-21 01:30:00.000000000Z · restored \
           tmux_recovery_1784597559000000000_0123abcd.snapshot"
    ; conflicts = []
    ; warnings = []
    }
;;

let make_app ~initial_recovery ~snapshots ~services =
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
      ?initial_recovery
      ~initial_snapshots:snapshots
      ~initial_services:services
      ~exit:(fun () -> Effect.Ignore)
      ~dimensions
      graph
;;

let app = make_app ~initial_recovery:None ~snapshots ~services

let warning_app =
  let decision : Recovery.decision =
    { pane_id = "%1"
    ; observed = "codex"
    ; action = Blocked
    ; executable = None
    ; argv = []
    ; fidelity = "shell fallback"
    ; reason = "Codex is running, but no durable thread reference is available"
    ; rule_id = Some "adapter:codex:missing-thread"
    }
  in
  let recovery : Recovery.plan =
    { source = Live
    ; decisions = [ decision ]
    ; warnings = [ "one application cannot resume exactly" ]
    }
  in
  make_app ~initial_recovery:(Some recovery) ~snapshots ~services
;;

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
      ; last_restore = None
      ; conflicts = []
      ; warnings = []
      }
  in
  make_app ~initial_recovery:None ~snapshots ~services
;;

let unavailable_app =
  make_app
    ~initial_recovery:None
    ~snapshots:(Or_error.error_string "fixture snapshot directory is unreadable")
    ~services:(Or_error.error_string "fixture service manager is unavailable")
;;
