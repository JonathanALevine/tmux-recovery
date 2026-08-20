open! Core
open Async

module Autonomy = Tmux_recovery_domain.Autonomy
module Recovery = Tmux_recovery_domain.Recovery
module Workspace = Tmux_recovery_domain.Workspace
module Runner = Tmux_recovery_application.Autonomy
module Store = Autonomy_store
module Domain_snapshot = Tmux_recovery_domain.Snapshot

let t0 = Time_ns.epoch
let at (seconds : int) = Time_ns.add t0 (Time_ns.Span.of_int_sec seconds)

let get (r : 'a ref) = !r

let ok_or_failwith (r : 'a Or_error.t) : 'a =
  (match r with
   | Ok x -> x
   | Error e -> failwith (Error.to_string_hum e))

(** Run the scheduler until [d] resolves and return its value. *)
let await (d : 'a Deferred.t) : 'a =
  let ivar = Ivar.create () in
  let _ =
    Deferred.bind d ~f:(fun x ->
      Ivar.fill_exn ivar x;
      Deferred.unit)
  in
  Async_kernel_scheduler.Expert.run_cycles_until_no_jobs_remain ();
  Ivar.value_exn ivar
;;

let snapshot_id = "tmux_recovery_1700000000000000000_deadbeef.snapshot"

(* Mutable test world: the runner's injected dependencies read from these refs
   so a single test can simulate time passing, clients attaching, panes going
   active, or the window becoming recoverable between ticks. *)
type world =
  { now_ref : Time_ns.t ref
  ; observed_count : int ref
  (** [blocked_after]: the workspace returned by observe call #n keeps @2
      blocked while n <= blocked_after; later observes report @2 recoverable. *)
  ; blocked_after : int ref
  ; viewed_ref : string list ref
  ; sig_ref : (string * string) list ref
  (** Optional (window_id, signature) overrides; the default signature is "s1". *)
  ; snapshot_ref : string option ref
  ; closed_ref : string list ref
  ; close_error_ref : bool ref
  }

let default_world () =
  { now_ref = ref t0
  ; observed_count = ref 0
  ; blocked_after = ref 1_000_000
  ; viewed_ref = ref []
  ; sig_ref = ref []
  ; snapshot_ref = ref (Some snapshot_id)
  ; closed_ref = ref []
  ; close_error_ref = ref false
  }
;;

let workspace ~blocked () =
  let sessions : Workspace.Session.t list = [ { id = "$2"; name = "idle"; attached = false } ] in
  let windows : Workspace.Window.t list =
    [ { id = "@2"; name = "w2"; layout = "layout-2" } ]
  in
  let links : Workspace.Window_link.t list =
    [ { id = "$2/@2"; session_id = "$2"; window_id = "@2"; index = 0; active = true } ]
  in
  let command = if blocked then "codex" else "btop" in
  let panes : Workspace.Pane.t list =
    [ { id = "%2"
      ; window_id = "@2"
      ; index = 0
      ; active = true
      ; title = ""
      ; cwd = "/tmp"
      ; current_command = command
      ; pid = Some 2
      ; tty = None
      }
    ]
  in
  let server : Workspace.Server.t = { available = true; socket = None; version = None } in
  Workspace.create ~source:Live ~server sessions windows links panes
  |> Result.map_error ~f:(String.concat ~sep:"; ")
  |> Result.ok_or_failwith
;;

let make_deps (world : world) : Runner.deps =
  { now = (fun () -> get world.now_ref)
  ; observe =
      (fun () ->
       world.observed_count := get world.observed_count + 1;
       let blocked = get world.observed_count <= get world.blocked_after in
       Deferred.return (Ok (workspace ~blocked ())))
  ; plan = (fun workspace -> Deferred.return (Ok (Recovery.plan workspace)))
  ; viewed = (fun () -> Deferred.return (Ok (get world.viewed_ref)))
  ; signature =
      (fun ~window_id ->
       let signature =
         match List.find (get world.sig_ref) ~f:(fun (id, _) -> String.equal id window_id) with
         | Some (_, s) -> s
         | None -> "s1"
       in
       Deferred.return (Ok signature))
  ; server_identity = (fun () -> Deferred.return (Ok "server-1"))
  ; snapshot_save =
      (fun () ->
       (match get world.snapshot_ref with
        | Some id ->
          (match Domain_snapshot.Id.of_string id with
           | Ok id ->
             Deferred.return
               (Ok
                  { Domain_snapshot.id = id
                  ; created_at = get world.now_ref
                  ; size_bytes = 1L
                  ; latest = true
                  ; last_good = true
                  ; validity = Domain_snapshot.Valid
                  ; warnings = []
                  ; session_count = 1
                  ; window_count = 1
                  ; pane_count = 1
                  ; manifest = true
                  ; legacy = false
                  })
           | Error e -> Deferred.return (Error e))
        | None -> Deferred.return (Error (Error.of_string "snapshot unavailable"))))
  ; close_window =
      (fun ~window_id ->
       if get world.close_error_ref
       then Deferred.return (Error (Error.of_string "tmux refused to close the window"))
       else (
         world.closed_ref := window_id :: get world.closed_ref;
         Deferred.return (Ok ())))
  }
;;

let with_world ~f =
  let world = default_world () in
  let dir = "/tmp/tr-runner-test-" ^ Int.to_string (Caml_unix.getpid ()) in
  let store =
    (Or_error.try_with_join (fun () ->
       Core_unix.mkdir_p dir ~perm:0o700;
       Store.create ~config_home:dir ~state_home:dir ()))
    |> ok_or_failwith
  in
  let runner = Runner.create ~store ~deps:(make_deps world) () in
  let unlink path = (try Core_unix.unlink path with Caml_unix.Unix_error _ -> ()) in
  let rmdir path = (try Core_unix.rmdir path with Caml_unix.Unix_error _ -> ()) in
  let result =
    Monitor.protect (fun () -> Deferred.return (f world (ok_or_failwith runner))) ~finally:(fun () ->
      let sub = dir ^/ "tmux-recovery" in
      unlink (sub ^/ "autonomy.json");
      unlink (sub ^/ "autonomy-state.json");
      unlink (sub ^/ "autonomy-audit.jsonl");
      unlink (sub ^/ "autonomy.lock");
      rmdir sub;
      rmdir dir;
      Deferred.unit)
  in
  await result
;;

let tick (runner : Runner.t) = ok_or_failwith (await (Runner.tick runner))
;;

let status (runner : Runner.t) = ok_or_failwith (await (Runner.status runner))
;;

let configure runner ?mode ?grace_seconds ?persistence_seconds ?snapshot_before_fire () =
  ok_or_failwith
    (await
       (Runner.configure runner ?mode ?grace_seconds ?persistence_seconds ?snapshot_before_fire ()))
;;

let outcome_of (runner : Runner.t) ~id =
  let info = status runner in
  (match List.find (List.append info.active info.archived) ~f:(fun a -> String.equal a.id id) with
   | Some a -> a.outcome
   | None -> failwith (Printf.sprintf "action %s not found" id))
;;

let is_fired ~dry_run outcome =
  (match outcome with
   | Autonomy.Fired f -> Bool.equal f.dry_run dry_run
   | _ -> false)
;;

let is_aborted outcome =
  (match outcome with
   | Autonomy.Aborted _ -> true
   | _ -> false)
;;

let is_cancelled outcome =
  (match outcome with
   | Autonomy.Cancelled _ -> true
   | _ -> false)
;;

let%test_unit "dry-run: a due action is recorded durably and nothing is executed" =
  with_world ~f:(fun world runner ->
    configure runner ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    (match tick runner with
     | Runner.Reconciled { state ; fired = None ; _ } ->
       assert (List.length (Autonomy.active state) = 1)
     | _ -> failwith "act-1 was not scheduled at t11");
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | Some id ->
          assert (String.equal id "act-1");
          assert (List.length (Autonomy.active r.state) = 0)
        | None -> failwith "the dry-run fire was not recorded")
     | _ -> failwith "the dry-run fire was not recorded");
    assert (List.is_empty (get world.closed_ref));
    assert (is_fired ~dry_run:true (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "live: a due action snapshots then closes the exact window" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | Some id -> assert (String.equal id "act-1")
        | None -> failwith "the live fire was not processed")
     | _ -> failwith "the live fire was not processed");
    assert (String.Set.equal (String.Set.of_list (get world.closed_ref)) (String.Set.of_list ["@2"]));
    let outcome = outcome_of runner ~id:"act-1" in
    assert (is_fired ~dry_run:false outcome);
    (match outcome with
     | Autonomy.Fired f ->
       assert (Option.is_some f.snapshot_id);
       assert (String.equal (Option.value_exn f.snapshot_id) snapshot_id)
     | _ -> failwith "expected Fired")
  )
;;

let%test_unit "live: a recheck failure aborts the fire and closes nothing" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    (* four observes so far (one per tick); the fire-time recheck is observe #5:
       @2 is no longer blocked, so the target no longer matches. *)
    world.blocked_after := 4;
    let _ = tick runner in
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | Some _ -> ()
        | None -> failwith "the due action was not processed")
     | _ -> failwith "the due action was not processed");
    assert (List.is_empty (get world.closed_ref));
    assert (is_aborted (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "live: a snapshot failure aborts the fire and closes nothing" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.snapshot_ref := None;
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    world.now_ref := at 111;
    let _ = tick runner in
    assert (List.is_empty (get world.closed_ref));
    assert (is_aborted (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "a window that becomes viewed drops out of the funnel and is auto-cancelled" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    (* A client now views @2: the pending action is auto-cancelled before the
       deadline, and the due tick closes nothing. *)
    world.viewed_ref := ["@2"];
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "nothing should be due once the window is viewed")
     | _ -> failwith "nothing should be due once the window is viewed");
    assert (List.is_empty (get world.closed_ref));
    assert (is_cancelled (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "an activity change resets eligibility and auto-cancels the pending action" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    world.sig_ref := [ "@2", "s2" ];
    world.now_ref := at 21;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "an active window cannot stay scheduled")
     | _ -> failwith "an active window cannot stay scheduled");
    world.now_ref := at 200;
    let _ = tick runner in
    assert (List.is_empty (get world.closed_ref));
    assert (is_cancelled (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "cancelling a pending action prevents its fire" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    ok_or_failwith (await (Runner.cancel runner ~id:"act-1"));
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "a cancelled action must not fire")
     | _ -> failwith "a cancelled action must not fire");
    assert (List.is_empty (get world.closed_ref));
    assert (is_cancelled (outcome_of runner ~id:"act-1"))
  )
;;

let%test_unit "pause clears the funnel; resume never fires an overdue action immediately" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    ok_or_failwith (await (Runner.pause runner));
    (* Far past the original deadline; the funnel was cleared, so even a fully
       eligible window must restart its persistence period. *)
    world.now_ref := at 10_000;
    ok_or_failwith (await (Runner.resume runner));
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "resume must not fire an overdue action immediately")
     | _ -> failwith "resume must not fire an overdue action immediately");
    assert (List.is_empty (get world.closed_ref))
  )
;;

let%test_unit "off mode skips ticks without observing the workspace" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Off ();
    let before = get world.observed_count in
    (match tick runner with
     | Runner.Skipped _ -> ()
     | Runner.Reconciled _ -> failwith "off mode must skip");
    assert (get world.observed_count = before)
  )
;;

let%test_unit "status reports policy, funnel, and pending actions" =
  with_world ~f:(fun world runner ->
    configure runner ~grace_seconds:100 ~persistence_seconds:10 ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    let info = status runner in
    assert (info.policy.grace_seconds = 100);
    assert (not info.paused);
    assert (List.length info.active = 1);
    let candidate_ids, _, _ = List.hd_exn info.candidates in
    assert (String.equal candidate_ids "@2");
    assert (List.exists info.audit ~f:(fun line -> String.contains line 's'))
  )
;;

let%test_unit "a close failure is recorded as Failed and closes nothing" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
    world.close_error_ref := true;
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | Some _ -> ()
        | None -> failwith "the due action must be processed")
     | _ -> failwith "the due action must be processed");
    assert (List.is_empty (get world.closed_ref));
    (match outcome_of runner ~id:"act-1" with
     | Autonomy.Failed _ -> ()
     | _ -> failwith "a failed close must be recorded as Failed")
  )
;;
