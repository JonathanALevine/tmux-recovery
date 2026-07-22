open! Core
module Recovery = Tmux_recovery_domain.Recovery
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Native_snapshot = Tmux_recovery_domain.Native_snapshot
module Workspace = Tmux_recovery_domain.Workspace

let sample_workspace () =
  let sessions : Workspace.Session.t list =
    [ { id = "$1"; name = "development"; attached = true }
    ; { id = "$2"; name = "research"; attached = false }
    ]
  in
  let windows : Workspace.Window.t list =
    [ { id = "@1"; name = "editor"; layout = "layout-a" } ]
  in
  let links : Workspace.Window_link.t list =
    [ { id = "$1/@1"; session_id = "$1"; window_id = "@1"; index = 0; active = true }
    ; { id = "$2/@1"; session_id = "$2"; window_id = "@1"; index = 2; active = true }
    ]
  in
  let panes : Workspace.Pane.t list =
    [ { id = "%1"
      ; window_id = "@1"
      ; index = 0
      ; active = true
      ; title = "monitor"
      ; cwd = "/tmp"
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

let%test_unit "a linked window remains one canonical object" =
  let workspace = sample_workspace () in
  [%test_eq: int] (Map.length workspace.sessions) 2;
  [%test_eq: int] (Map.length workspace.windows) 1;
  [%test_eq: int] (List.length workspace.window_links) 2;
  [%test_eq: int] (Map.length workspace.panes) 1;
  [%test_eq: int] (Workspace.linked_session_count workspace ~window_id:"@1") 2
;;

let%test_unit "the built-in catalog makes conservative decisions" =
  let workspace = sample_workspace () in
  let plan : Recovery.plan = Recovery.plan workspace in
  let decision = List.hd_exn plan.decisions in
  [%test_eq: int] (List.length plan.decisions) 1;
  [%test_eq: string] decision.pane_id "%1";
  [%test_eq: string] decision.observed "btop";
  [%test_eq: Recovery.Action.t] decision.action Restart;
  [%test_eq: string] decision.fidelity "new application instance"
;;

let%test_unit "unknown programs fall back to a usable shell" =
  let pane : Workspace.Pane.t =
    { id = "%9"
    ; window_id = "@9"
    ; index = 0
    ; active = true
    ; title = ""
    ; cwd = "/tmp"
    ; current_command = "mystery-agent"
    ; pid = None
    ; tty = None
    }
  in
  let decision = Recovery.classify pane in
  [%test_eq: Recovery.Action.t] decision.action Shell_fallback;
  [%test_eq: string option] decision.executable None;
  [%test_eq: string] decision.reason "no approved recovery rule for mystery-agent"
;;

let%test_unit "tmux-recovery relaunches its own interactive navigator" =
  let pane : Workspace.Pane.t =
    { id = "%10"
    ; window_id = "@10"
    ; index = 0
    ; active = true
    ; title = "tmux-recovery"
    ; cwd = "/tmp"
    ; current_command = "tmux-recovery"
    ; pid = Some 100
    ; tty = None
    }
  in
  let decision = Recovery.classify pane in
  [%test_eq: Recovery.Action.t] decision.action Restart;
  [%test_eq: string option] decision.executable (Some "tmux-recovery");
  [%test_eq: string] decision.fidelity "new interactive recovery navigator";
  [%test_eq: string option] decision.rule_id (Some "builtin:tmux-recovery")
;;

let%test_unit "Codex panes resume only with a validated durable thread reference" =
  let pane : Workspace.Pane.t =
    { id = "%9"
    ; window_id = "@9"
    ; index = 0
    ; active = true
    ; title = "codex"
    ; cwd = "/tmp"
    ; current_command = "codex"
    ; pid = Some 99
    ; tty = None
    }
  in
  let blocked = Recovery.classify pane in
  [%test_eq: Recovery.Action.t] blocked.action Blocked;
  let resume =
    Recovery.Codex_resume.create
      ~thread_id:"019f8c7e-1234-7abc-8def-0123456789ab"
      ~cwd:"/tmp"
      ~bypass_approvals:true
    |> Or_error.ok_exn
  in
  let decision = Recovery.classify ~codex_resume:resume pane in
  [%test_eq: Recovery.Action.t] decision.action Resume;
  [%test_eq: string option] decision.executable (Some "codex");
  assert (
    List.mem
      decision.argv
      "--dangerously-bypass-approvals-and-sandbox"
      ~equal:String.equal)
;;

let%test_unit "malformed Codex thread references are rejected" =
  assert (
    Result.is_error
      (Recovery.Codex_resume.create
         ~thread_id:"../../not-a-thread"
         ~cwd:"/tmp"
         ~bypass_approvals:false))
;;

let%test_unit "invalid graph relationships are rejected before rendering" =
  let workspace = sample_workspace () in
  let duplicate = List.hd_exn workspace.window_links in
  let invalid = { workspace with window_links = duplicate :: workspace.window_links } in
  match Workspace.validate invalid with
  | Ok () -> failwith "duplicate link unexpectedly passed validation"
  | Error errors ->
    assert (List.mem errors "duplicate window link id: $1/@1" ~equal:String.equal)
;;

let%test_unit "snapshot IDs are basenames with a fixed timestamp shape" =
  let id =
    Snapshot.Id.of_string "tmux_resurrect_20260720T213239.txt" |> Or_error.ok_exn
  in
  [%test_eq: string] (Snapshot.Id.to_string id) "tmux_resurrect_20260720T213239.txt";
  [%test_eq: string] (Snapshot.Id.display_time id) "2026-07-20 21:32:39";
  assert (Result.is_error (Snapshot.Id.of_string "../tmux_resurrect_20260720T213239.txt"));
  assert (Result.is_error (Snapshot.Id.of_string "tmux_resurrect_latest.txt"))
;;

let%test_unit "native snapshot IDs and JSON round-trip the canonical graph" =
  let created_at =
    Time_ns.of_int63_ns_since_epoch (Int63.of_string "1784664000123456789")
  in
  let id = Snapshot.Id.create_native ~created_at ~nonce:"00a1b2c3" |> Or_error.ok_exn in
  [%test_eq: Snapshot.Id.kind] (Snapshot.Id.kind id) Native;
  assert (not (String.is_substring (Snapshot.Id.to_string id) ~substring:"/"));
  let snapshot =
    let resume =
      Recovery.Codex_resume.create
        ~thread_id:"019f8c7e-1234-7abc-8def-0123456789ab"
        ~cwd:"/tmp"
        ~bypass_approvals:false
      |> Or_error.ok_exn
    in
    Native_snapshot.create
      ~codex_resumes:(String.Map.singleton "%1" resume)
      ~id
      ~created_at
      ~trigger:Manual
      ~tool_version:"test"
      (sample_workspace ())
    |> Or_error.ok_exn
  in
  let decoded =
    Native_snapshot.to_yojson snapshot |> Native_snapshot.of_yojson |> Or_error.ok_exn
  in
  [%test_eq: Snapshot.Id.t] decoded.id id;
  [%test_eq: int] (Map.length decoded.codex_resumes) 1;
  let expected =
    { snapshot.workspace with
      source = Snapshot (Snapshot.Id.to_string id)
    ; server = { snapshot.workspace.server with available = false; socket = None }
    }
  in
  assert (Workspace.equal decoded.workspace expected)
;;

let%test_unit "service vocabulary stays manager-neutral" =
  [%test_eq: string] (Service.manager_label Launchd) "launchd";
  [%test_eq: string] (Service.manager_label Systemd) "systemd --user";
  [%test_eq: string] (Service.ownership_label Legacy) "legacy/unmanaged";
  [%test_eq: string] (Service.ownership_label Managed) "tmux-recovery-managed";
  [%test_eq: string] (Service.activation_label Loaded) "loaded"
;;
