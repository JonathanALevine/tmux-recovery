open! Core
module Autonomy = Tmux_recovery_domain.Autonomy
module Recovery = Tmux_recovery_domain.Recovery
module Workspace = Tmux_recovery_domain.Workspace

let t0 = Time_ns.epoch
let at (seconds : int) = Time_ns.add t0 (Time_ns.Span.of_int_sec seconds)

let has_substring (haystack : string) (needle : string) =
  let len = String.length needle in
  if len > String.length haystack
  then false
  else
    let rec loop i =
      i + len <= String.length haystack
      && (
        String.equal (String.sub haystack ~pos:i ~len) needle
        || loop (i + 1))
    in
    loop 0
;;

let dry_config : Autonomy.config =
  { mode = Autonomy.Mode.Dry_run
  ; grace_seconds = 100
  ; persistence_seconds = 10
  ; snapshot_before_fire = true
  }
;;

(* A workspace with three windows:
   - @1 is blocked (codex) but viewed by a client -> never a candidate.
   - @2 is blocked (codex) and unviewed (its session is even attached; the client
     looks at @1) -> a candidate.
   - @3 is recoverable (btop) -> never a candidate. *)
let test_workspace () =
  let sessions : Workspace.Session.t list =
    [ { id = "$1"; name = "work"; attached = true }
    ; { id = "$2"; name = "idle"; attached = false }
    ]
  in
  let windows : Workspace.Window.t list =
    [ { id = "@1"; name = "w1"; layout = "layout-1" }
    ; { id = "@2"; name = "w2"; layout = "layout-2" }
    ; { id = "@3"; name = "w3"; layout = "layout-3" }
    ]
  in
  let links : Workspace.Window_link.t list =
    [ { id = "$1/@1"; session_id = "$1"; window_id = "@1"; index = 0; active = true }
    ; { id = "$2/@2"; session_id = "$2"; window_id = "@2"; index = 0; active = true }
    ; { id = "$2/@3"; session_id = "$2"; window_id = "@3"; index = 1; active = false }
    ]
  in
  let panes : Workspace.Pane.t list =
    [ { id = "%1"
      ; window_id = "@1"
      ; index = 0
      ; active = true
      ; title = ""
      ; cwd = "/tmp"
      ; current_command = "codex"
      ; pid = Some 1
      ; tty = None
      }
    ; { id = "%2"
      ; window_id = "@2"
      ; index = 0
      ; active = true
      ; title = ""
      ; cwd = "/tmp"
      ; current_command = "codex"
      ; pid = Some 2
      ; tty = None
      }
    ; { id = "%3"
      ; window_id = "@3"
      ; index = 0
      ; active = true
      ; title = ""
      ; cwd = "/tmp"
      ; current_command = "btop"
      ; pid = Some 3
      ; tty = None
      }
    ]
  in
  let server : Workspace.Server.t = { available = true; socket = None; version = None } in
  Workspace.create ~source:Live ~server sessions windows links panes
  |> Result.map_error ~f:(String.concat ~sep:"; ")
  |> Result.ok_or_failwith
;;

let test_plan () = Recovery.plan (test_workspace ())

let target_for (window_id : string) : Autonomy.target =
  let server_identity = "server-1" in
  let session_id, window_name, window_layout, panes =
    match window_id with
    | "@1" -> "$1", "w1", "layout-1", [ "%1", "codex" ]
    | "@2" -> "$2", "w2", "layout-2", [ "%2", "codex" ]
    | _ -> failwith "unexpected window"
  in
  { window_id
  ; session_id
  ; server_identity
  ; window_name
  ; window_layout
  ; panes
  }
;;

let candidate ~window_id ~signature : Autonomy.candidate =
  { target = target_for window_id
  ; reason = "no durable Codex thread reference was captured for this pane"
  ; signature
  }
;;

let tick_candidate state now ~window_id ~signature =
  Autonomy.tick ~now ~candidates:[ candidate ~window_id ~signature ] state
;;

let fresh () = Autonomy.empty ~config:dry_config

(* A state in which window @2 was first observed at t0 and again, unchanged, at t1;
   its eligibility clock therefore started at t1, and by t11 (10s later) the
   persistence threshold is met: act-1 is scheduled at t11 with deadline t111. *)
let scheduled_state () =
  let state = fresh () in
  let state = tick_candidate state (at 0) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 1) ~window_id:"@2" ~signature:"s1" in
  Autonomy.tick ~now:(at 11) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state
;;

let%test_unit "detect flags only blocked windows that no client is viewing" =
  let workspace = test_workspace ()
  and recovery = test_plan () in
  (* The client views @1, so even though @2's session $2 is unattached and @1's
     session $1 is attached, only the exact viewed window is protected. *)
  let found = Autonomy.detect ~workspace ~recovery ~viewed:[ "@1" ] in
  [%test_eq: (string * string * string) list]
    found
    [ "@2", "$2", "no durable Codex thread reference was captured for this pane" ];
  (* Nothing viewed: both blocked windows are candidates. *)
  let found = Autonomy.detect ~workspace ~recovery ~viewed:[] in
  [%test_eq: int] (List.length found) 2;
  (* Viewing @2 protects exactly that window. *)
  let found = Autonomy.detect ~workspace ~recovery ~viewed:[ "@2" ] in
  [%test_eq: string list]
    (List.map found ~f:(fun (w, _, _) -> w))
    [ "@1" ]
;;

let%test_unit "the first activity sample is never quiescent" =
  let state = fresh () in
  let state = tick_candidate state (at 0) ~window_id:"@2" ~signature:"s1" in
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  let entries = Autonomy.candidates state in
  [%test_eq: (string * Time_ns.t option * bool) list]
    entries
    [ "@2", None, false ]
;;

let%test_unit "an unchanged second sample starts the eligibility clock" =
  let state = fresh () in
  let state = tick_candidate state (at 0) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 30) ~window_id:"@2" ~signature:"s1" in
  let entries = Autonomy.candidates state in
  [%test_eq: (string * Time_ns.t option * bool) list] entries [ "@2", Some (at 30), false ];
  (* Persistence (10s) is not yet met: 30 -> 35 is only 5s of eligibility. *)
  let state = Autonomy.tick ~now:(at 35) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  [%test_eq: int] (List.length (Autonomy.active state)) 0
;;

let%test_unit "activity changes reset persistence" =
  let state = fresh () in
  let state = tick_candidate state (at 0) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 1) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 11) ~window_id:"@2" ~signature:"s1" in
  (* Eligibility started at t=1; persistence (10s) is met at t=11. *)
  let scheduled = Autonomy.active state in
  [%test_eq: int] (List.length scheduled) 1;
  (* Now the signature changes: the pending action is auto-cancelled and the clock
     resets. *)
  let state = tick_candidate state (at 31) ~window_id:"@2" ~signature:"s2" in
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  let action = Option.value_exn (Autonomy.latest_action_for_window state ~window_id:"@2") in
  (match action.outcome with
   | Autonomy.Cancelled { reason; _ } ->
     [%test_eq: string] reason "activity changed during the grace countdown"
   | _ -> failwith "expected an auto-cancelled action");
  (* The window is suppressed: it cannot be re-scheduled in this cycle even after
     the new signature persists. *)
  let state = tick_candidate state (at 41) ~window_id:"@2" ~signature:"s2" in
  let state = tick_candidate state (at 61) ~window_id:"@2" ~signature:"s2" in
  let state = tick_candidate state (at 81) ~window_id:"@2" ~signature:"s2" in
  [%test_eq: int] (List.length (Autonomy.active state)) 0
;;

let%test_unit "continuous persistence schedules an action with a grace deadline" =
  let state = scheduled_state () in
  let scheduled = Autonomy.active state in
  [%test_eq: int] (List.length scheduled) 1;
  let action = List.hd_exn scheduled in
  [%test_eq: string] action.window_id "@2";
  [%test_eq: string] action.id "act-1";
  [%test_eq: Time_ns.t] action.scheduled_at (at 11);
  [%test_eq: Time_ns.t] action.deadline (at 111);
  [%test_eq: Autonomy.outcome] action.outcome Autonomy.Scheduled;
  [%test_eq: string] action.target.server_identity "server-1";
  [%test_eq: (string * string) list] action.target.panes [ "%2", "codex" ]
;;

let%test_unit "action IDs are unique across re-arming cycles" =
  let state = scheduled_state () in
  let state = Autonomy.abort_fire ~now:(at 111) ~id:"act-1" ~reason:"test" state in
  (* The window leaves the funnel... *)
  let state = Autonomy.tick ~now:(at 120) ~candidates:[] state in
  (* ...and re-enters later: a fresh cycle produces a new action ID. *)
  let state = tick_candidate state (at 130) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 140) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 150) ~window_id:"@2" ~signature:"s1" in
  let scheduled = Autonomy.active state in
  [%test_eq: int] (List.length scheduled) 1;
  [%test_eq: string] (List.hd_exn scheduled).id "act-2"
;;

let%test_unit "remaining counts down and clamps at zero" =
  let state = scheduled_state () in
  let action = List.hd_exn (Autonomy.active state) in
  [%test_eq: Time_ns.Span.t]
    (Autonomy.remaining ~now:(at 11) action)
    (Time_ns.Span.of_int_sec 100);
  [%test_eq: Time_ns.Span.t]
    (Autonomy.remaining ~now:(at 61) action)
    (Time_ns.Span.of_int_sec 50);
  [%test_eq: Time_ns.Span.t] (Autonomy.remaining ~now:(at 120) action) Time_ns.Span.zero
;;

let%test_unit "due reports actions only once past their deadline" =
  let state = scheduled_state () in
  [%test_eq: int] (List.length (Autonomy.due ~now:(at 110) state)) 0;
  [%test_eq: int] (List.length (Autonomy.due ~now:(at 111) state)) 1
;;

let%test_unit "apply_fire records the snapshot id, dry-run flag, and note" =
  let state = scheduled_state () in
  let state =
    Autonomy.apply_fire ~now:(at 111) ~id:"act-1" ~snapshot_id:"snap-1" ~dry_run:false ~note:"closed" state
  in
  let action = Option.value_exn (Autonomy.find_action state ~id:"act-1") in
  (match action.outcome with
   | Autonomy.Fired { snapshot_id; note; dry_run; _ } ->
     [%test_eq: string option] snapshot_id (Some "snap-1");
     [%test_eq: string] note "closed";
     [%test_eq: bool] dry_run false
   | _ -> failwith "expected a Fired action")
;;

let%test_unit "abort_fire and fail_fire archive with reasons" =
  let state = scheduled_state () in
  let state = Autonomy.abort_fire ~now:(at 111) ~id:"act-1" ~reason:"snapshot failed" state in
  (match (Option.value_exn (Autonomy.find_action state ~id:"act-1")).outcome with
   | Autonomy.Aborted { reason; _ } -> [%test_eq: string] reason "snapshot failed"
   | _ -> failwith "expected Aborted");
  let state2 = scheduled_state () in
  let state2 = Autonomy.fail_fire ~now:(at 111) ~id:"act-1" ~reason:"kill-window failed" state2 in
  (match (Option.value_exn (Autonomy.find_action state2 ~id:"act-1")).outcome with
   | Autonomy.Failed { reason; _ } -> [%test_eq: string] reason "kill-window failed"
   | _ -> failwith "expected Failed")
;;

let%test_unit "cancel targets the selected action ID and suppresses the cycle" =
  let state = scheduled_state () in
  let state = Autonomy.cancel ~now:(at 50) ~id:"act-1" state in
  (match (Option.value_exn (Autonomy.find_action state ~id:"act-1")).outcome with
   | Autonomy.Cancelled { reason; _ } -> [%test_eq: string] reason "cancelled by user"
   | _ -> failwith "expected Cancelled");
  (* Even though @2 is still a candidate, the current cycle is suppressed. *)
  let state = Autonomy.tick ~now:(at 60) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  let state = Autonomy.tick ~now:(at 90) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  (* Cancelling an unknown or terminal action ID is a no-op. *)
  let state = Autonomy.cancel ~now:(at 100) ~id:"act-99" state in
  [%test_eq: Autonomy.state] state (Autonomy.cancel ~now:(at 101) ~id:"act-1" state)
;;

let%test_unit "a window leaving the funnel auto-cancels its pending action" =
  let state = scheduled_state () in
  let state = Autonomy.tick ~now:(at 20) ~candidates:[] state in
  (match (Option.value_exn (Autonomy.latest_action_for_window state ~window_id:"@2")).outcome with
   | Autonomy.Cancelled { reason; _ } ->
     [%test_eq: string] reason "window left the eligibility funnel"
   | _ -> failwith "expected a Cancelled action");
  let entries = Autonomy.candidates state in
  [%test_eq: int] (List.length entries) 0
;;

let%test_unit "re-arming requires leaving the funnel and re-entering" =
  let state = scheduled_state () in
  let state = Autonomy.cancel ~now:(at 20) ~id:"act-1" state in
  (* Still a candidate every tick: never re-scheduled in the same cycle. *)
  let state = Autonomy.tick ~now:(at 30) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  let state = Autonomy.tick ~now:(at 60) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  let state = Autonomy.tick ~now:(at 90) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  (* Leaves the funnel, then re-enters: a fresh cycle schedules again. *)
  let state = Autonomy.tick ~now:(at 100) ~candidates:[] state in
  let state = tick_candidate state (at 110) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 120) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 130) ~window_id:"@2" ~signature:"s1" in
  [%test_eq: int] (List.length (Autonomy.active state)) 1
;;

let%test_unit "pause cancels pending deadlines and clears the funnel" =
  let state = scheduled_state () in
  let state = Autonomy.pause ~now:(at 50) state in
  [%test_eq: bool] (Autonomy.paused state) true;
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  [%test_eq: int] (List.length (Autonomy.candidates state)) 0;
  (match (Option.value_exn (Autonomy.find_action state ~id:"act-1")).outcome with
   | Autonomy.Cancelled { reason; _ } -> [%test_eq: string] reason "paused"
   | _ -> failwith "expected Cancelled");
  (* The pause audit entry reports how many pending actions were cancelled. *)
  [%test_eq: bool]
    (List.exists (Autonomy.audit_lines state)
       ~f:(fun l -> has_substring l "cancelled 1 pending action(s)"))
    true
;;

let%test_unit "ticks do nothing while paused and resume never fires overdue actions" =
  let state = scheduled_state () in
  let state = Autonomy.pause ~now:(at 50) state in
  (* Candidate observations while paused accumulate nothing. *)
  let state = Autonomy.tick ~now:(at 60) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  let state = Autonomy.tick ~now:(at 90) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  let state = Autonomy.resume ~now:(at 100) state in
  [%test_eq: bool] (Autonomy.paused state) false;
  (* The old deadline (t0+110) is in the past, but no action survives the pause, so
     nothing is due. *)
  [%test_eq: int] (List.length (Autonomy.due ~now:(at 120) state)) 0;
  (* A fresh persistence period is required before a new action can be scheduled. *)
  let state = tick_candidate state (at 120) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 130) ~window_id:"@2" ~signature:"s1" in
  let state = tick_candidate state (at 140) ~window_id:"@2" ~signature:"s1" in
  let scheduled = Autonomy.active state in
  [%test_eq: int] (List.length scheduled) 1;
  let action = List.hd_exn scheduled in
  [%test_eq: Time_ns.t] action.deadline (at 240);
  (* Pausing twice, or resuming twice, is a no-op. *)
  let state2 = Autonomy.pause ~now:(at 150) state in
  [%test_eq: Autonomy.state] (Autonomy.pause ~now:(at 151) state2) state2;
  let state3 = Autonomy.resume ~now:(at 160) state2 in
  [%test_eq: Autonomy.state] (Autonomy.resume ~now:(at 161) state3) state3
;;

let%test_unit "mode or threshold changes safely reset eligibility cycles" =
  let state = scheduled_state () in
  let live_config = { dry_config with mode = Autonomy.Mode.Live } in
  let state = Autonomy.with_config ~now:(at 50) live_config state in
  [%test_eq: Autonomy.Mode.t] state.config.mode Autonomy.Mode.Live;
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  [%test_eq: int] (List.length (Autonomy.candidates state)) 0;
  (match (Option.value_exn (Autonomy.find_action state ~id:"act-1")).outcome with
   | Autonomy.Cancelled { reason; _ } -> [%test_eq: string] reason "policy changed"
   | _ -> failwith "expected Cancelled");
  (* An identical config is a no-op. *)
  [%test_eq: Autonomy.state] (Autonomy.with_config ~now:(at 60) live_config state) state;
  (* A grace-only change also resets. *)
  let state =
    Autonomy.with_config ~now:(at 70) { dry_config with grace_seconds = 200 } state
  in
  [%test_eq: int] (List.length (Autonomy.candidates state)) 0
;;

let%test_unit "off mode schedules nothing and freezes the funnel" =
  let off_config : Autonomy.config = { dry_config with mode = Autonomy.Mode.Off } in
  let state = Autonomy.empty ~config:off_config in
  let state = Autonomy.tick ~now:(at 100) ~candidates:[ candidate ~window_id:"@2" ~signature:"s1" ] state in
  [%test_eq: int] (List.length (Autonomy.active state)) 0;
  [%test_eq: int] (List.length (Autonomy.candidates state)) 0;
  (* Switching back to dry-run resets the funnel cleanly. *)
  let state = Autonomy.with_config ~now:(at 110) dry_config state in
  [%test_eq: int] (List.length (Autonomy.candidates state)) 0
;;

let%test_unit "target_matches enforces server identity and window/pane fingerprint" =
  let state = scheduled_state () in
  let action = List.hd_exn (Autonomy.active state) in
  let with_target (target : Autonomy.target) : Autonomy.candidate =
    { target; reason = "r"; signature = "s1" }
  in
  let base = target_for "@2" in
  [%test_eq: unit Or_error.t] (Autonomy.target_matches action (with_target base)) (Ok ());
  let other_server = with_target { base with server_identity = "server-2" } in
  (match Autonomy.target_matches action other_server with
   | Error _ -> ()
   | Ok () -> failwith "expected a server identity mismatch");
  let renamed = with_target { base with window_name = "w2-renamed" } in
  (match Autonomy.target_matches action renamed with
   | Error _ -> ()
   | Ok () -> failwith "expected a window name mismatch");
  let repurposed = with_target { base with panes = [ "%2", "vim" ] } in
  (match Autonomy.target_matches action repurposed with
   | Error _ -> ()
   | Ok () -> failwith "expected a pane fingerprint mismatch")
;;

let%test_unit "the audit log records schedules, fires, cancellations, and pauses" =
  let state = scheduled_state () in
  let state =
    Autonomy.apply_fire ~now:(at 111) ~id:"act-1" ~snapshot_id:"s" ~dry_run:false ~note:"closed" state
  in
  let lines = Autonomy.audit_lines state in
  [%test_eq: bool]
    (List.exists lines ~f:(fun l -> has_substring l "scheduled act-1 @2"))
    true;
  [%test_eq: bool]
    (List.exists lines ~f:(fun l -> has_substring l "fired act-1 @2 closed"))
    true;
  let state2 = scheduled_state () in
  let state2 = Autonomy.pause ~now:(at 50) state2 in
  [%test_eq: bool]
    (List.exists (Autonomy.audit_lines state2) ~f:(fun l -> has_substring l "paused;"))
    true
;;

let%test_unit "state serializes to and from yojson without loss" =
  let state = scheduled_state () in
  let state =
    Autonomy.apply_fire ~now:(at 111) ~id:"act-1" ~snapshot_id:"s" ~dry_run:true ~note:"dry-run" state
  in
  let state = Autonomy.pause ~now:(at 120) state in
  let state = Autonomy.resume ~now:(at 130) state in
  let json = Autonomy.state_to_yojson state in
  let restored = Autonomy.state_of_yojson json |> Or_error.ok_exn in
  [%test_eq: Autonomy.state] restored state;
  (* Corrupt payloads fail closed instead of raising. *)
  (match Autonomy.state_of_yojson (`String "garbage") with
   | Error _ -> ()
   | Ok _ -> failwith "expected a parse failure")
;;
