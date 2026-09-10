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
  match r with
  | Ok x -> x
  | Error e -> failwith (Error.to_string_hum e)
;;

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

(* Mutable test world: the runner's injected dependencies read from these refs so a single
   test can simulate time passing, clients attaching, panes going active, or the window
   becoming recoverable between ticks. *)
type world =
  { now_ref : Time_ns.t ref
  ; observed_count : int ref
  (** [blocked_after]: the workspace returned by observe call #n keeps @2 blocked while n
      <= blocked_after; later observes report @2 recoverable. *)
  ; blocked_after : int ref
  ; plan_error_after : int ref
  ; exited_ref : String.Set.t ref
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
  ; plan_error_after = ref 1_000_000
  ; exited_ref = ref (String.Set.singleton "%2")
  ; viewed_ref = ref []
  ; sig_ref = ref []
  ; snapshot_ref = ref (Some snapshot_id)
  ; closed_ref = ref []
  ; close_error_ref = ref false
  }
;;

let workspace ~blocked () =
  let sessions : Workspace.Session.t list =
    [ { id = "$2"; name = "idle"; attached = false } ]
  in
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
  ; plan =
      (fun workspace ->
        Deferred.return
          (if get world.observed_count > get world.plan_error_after
           then Or_error.error_string "process inventory unavailable"
           else Ok (Recovery.plan workspace)))
  ; exited_panes = (fun () -> Deferred.return (Ok (get world.exited_ref)))
  ; viewed = (fun () -> Deferred.return (Ok (get world.viewed_ref)))
  ; signature =
      (fun ~window_id ->
        let signature =
          match
            List.find (get world.sig_ref) ~f:(fun (id, _) -> String.equal id window_id)
          with
          | Some (_, s) -> s
          | None -> "s1"
        in
        Deferred.return (Ok signature))
  ; server_identity = (fun () -> Deferred.return (Ok "server-1"))
  ; snapshot_save =
      (fun () ->
        match get world.snapshot_ref with
        | Some id ->
          (match Domain_snapshot.Id.of_string id with
           | Ok id ->
             Deferred.return
               (Ok
                  { Domain_snapshot.id
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
        | None -> Deferred.return (Error (Error.of_string "snapshot unavailable")))
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
    Or_error.try_with_join (fun () ->
      Core_unix.mkdir_p dir ~perm:0o700;
      Store.create ~config_home:dir ~state_home:dir ())
    |> ok_or_failwith
  in
  let runner = Runner.create ~store ~deps:(make_deps world) () in
  let unlink path =
    try Core_unix.unlink path with
    | Caml_unix.Unix_error _ -> ()
  in
  let rmdir path =
    try Core_unix.rmdir path with
    | Caml_unix.Unix_error _ -> ()
  in
  let result =
    Monitor.protect
      (fun () -> Deferred.return (f world (ok_or_failwith runner)))
      ~finally:(fun () ->
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
let status (runner : Runner.t) = ok_or_failwith (await (Runner.status runner))

let configure runner ?mode ?grace_seconds ?persistence_seconds ?snapshot_before_fire () =
  ok_or_failwith
    (await
       (Runner.configure
          runner
          ?mode
          ?grace_seconds
          ?persistence_seconds
          ?snapshot_before_fire
          ()))
;;

let outcome_of (runner : Runner.t) ~id =
  let info = status runner in
  match
    List.find (List.append info.active info.archived) ~f:(fun a -> String.equal a.id id)
  with
  | Some a -> a.outcome
  | None -> failwith (Printf.sprintf "action %s not found" id)
;;

let is_fired outcome =
  match outcome with
  | Autonomy.Fired _ -> true
  | _ -> false
;;

let is_aborted outcome =
  match outcome with
  | Autonomy.Aborted _ -> true
  | _ -> false
;;

let is_cancelled outcome =
  match outcome with
  | Autonomy.Cancelled _ -> true
  | _ -> false
;;

let%test_unit "default off never observes, schedules, or executes cleanup" =
  with_world ~f:(fun world runner ->
    configure runner ~grace_seconds:100 ~persistence_seconds:10 ();
    List.iter [ 0; 1; 11; 111; 10000 ] ~f:(fun seconds ->
      world.now_ref := at seconds;
      match tick runner with
      | Runner.Skipped _ -> ()
      | Runner.Reconciled _ -> failwith "default policy must remain off");
    let info = status runner in
    assert (Autonomy.Mode.equal info.policy.mode Autonomy.Mode.Off);
    assert (List.is_empty info.active);
    assert (List.is_empty info.archived);
    assert (List.is_empty (get world.closed_ref));
    assert (get world.observed_count = 0))
;;

let%test_unit "live: a due action snapshots then closes the exact window" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    assert (
      String.Set.equal
        (String.Set.of_list (get world.closed_ref))
        (String.Set.of_list [ "@2" ]));
    let outcome = outcome_of runner ~id:"act-1" in
    assert (is_fired outcome);
    match outcome with
    | Autonomy.Fired f ->
      assert (Option.is_some f.snapshot_id);
      assert (String.equal (Option.value_exn f.snapshot_id) snapshot_id)
    | _ -> failwith "expected Fired")
;;

let%test_unit "live: a recheck failure aborts the fire and closes nothing" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    (* four observes so far (one per tick); the fire-time recheck is observe #5: @2 is no
       longer blocked, so the target no longer matches. *)
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
    assert (is_aborted (outcome_of runner ~id:"act-1")))
;;

let%test_unit "live: a snapshot failure aborts the fire and closes nothing" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    assert (is_aborted (outcome_of runner ~id:"act-1")))
;;

let%test_unit "a window that becomes viewed drops out of the funnel and is auto-cancelled"
  =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    (* A client now views @2: the pending action is auto-cancelled before the deadline,
       and the due tick closes nothing. *)
    world.viewed_ref := [ "@2" ];
    world.now_ref := at 111;
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "nothing should be due once the window is viewed")
     | _ -> failwith "nothing should be due once the window is viewed");
    assert (List.is_empty (get world.closed_ref));
    assert (is_cancelled (outcome_of runner ~id:"act-1")))
;;

let%test_unit "an activity change resets eligibility and auto-cancels the pending action" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    assert (is_cancelled (outcome_of runner ~id:"act-1")))
;;

let%test_unit "cancelling a pending action prevents its fire" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    assert (is_cancelled (outcome_of runner ~id:"act-1")))
;;

let%test_unit "pause clears the funnel; resume never fires an overdue action immediately" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
    world.now_ref := at 0;
    let _ = tick runner in
    world.now_ref := at 1;
    let _ = tick runner in
    world.now_ref := at 11;
    let _ = tick runner in
    ok_or_failwith (await (Runner.pause runner));
    (* Far past the original deadline; the funnel was cleared, so even a fully eligible
       window must restart its persistence period. *)
    world.now_ref := at 10_000;
    ok_or_failwith (await (Runner.resume runner));
    (match tick runner with
     | Runner.Reconciled r ->
       (match r.fired with
        | None -> ()
        | Some _ -> failwith "resume must not fire an overdue action immediately")
     | _ -> failwith "resume must not fire an overdue action immediately");
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "off mode skips ticks without observing the workspace" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Off ();
    let before = get world.observed_count in
    (match tick runner with
     | Runner.Skipped _ -> ()
     | Runner.Reconciled _ -> failwith "off mode must skip");
    assert (get world.observed_count = before))
;;

let%test_unit "status reports policy, funnel, and pending actions" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    assert (List.exists info.audit ~f:(fun line -> String.contains line 's')))
;;

let%test_unit "a close failure is recorded as Failed and closes nothing" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
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
    match outcome_of runner ~id:"act-1" with
    | Autonomy.Failed _ -> ()
    | _ -> failwith "a failed close must be recorded as Failed")
;;

let%test_unit "live unresolved Codex is never scheduled or closed" =
  with_world ~f:(fun world runner ->
    configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:0 ~persistence_seconds:0 ();
    world.exited_ref := String.Set.empty;
    List.iter [ 0; 1; 10000 ] ~f:(fun seconds ->
      world.now_ref := at seconds;
      ignore (tick runner : Runner.tick_result));
    assert (List.is_empty (status runner).active);
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "an observation outage cancels pending cleanup and restarts persistence" =
  with_world ~f:(fun world runner ->
    configure
      runner
      ~mode:Autonomy.Mode.Live
      ~grace_seconds:100
      ~persistence_seconds:10
      ();
    List.iter [ 0; 1; 11 ] ~f:(fun seconds ->
      world.now_ref := at seconds;
      ignore (tick runner : Runner.tick_result));
    world.plan_error_after := 3;
    world.now_ref := at 111;
    assert (Result.is_error (await (Runner.tick runner)));
    assert (List.is_empty (status runner).active);
    assert (is_cancelled (outcome_of runner ~id:"act-1"));
    world.plan_error_after := 1_000_000;
    world.now_ref := at 10000;
    ignore (tick runner : Runner.tick_result);
    assert (List.is_empty (status runner).active);
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "provider failures at either fire recheck abort the close" =
  List.iter [ 4; 5 ] ~f:(fun healthy_observations ->
    with_world ~f:(fun world runner ->
      configure
        runner
        ~mode:Autonomy.Mode.Live
        ~grace_seconds:100
        ~persistence_seconds:10
        ();
      List.iter [ 0; 1; 11 ] ~f:(fun seconds ->
        world.now_ref := at seconds;
        ignore (tick runner : Runner.tick_result));
      world.plan_error_after := healthy_observations;
      world.now_ref := at 111;
      ignore (tick runner : Runner.tick_result);
      assert (is_aborted (outcome_of runner ~id:"act-1"));
      assert (List.is_empty (get world.closed_ref))))
;;

let with_world_store ~f =
  with_world ~f:(fun world runner ->
    let dir = "/tmp/tr-runner-test-" ^ Int.to_string (Caml_unix.getpid ()) in
    let store = Store.create ~config_home:dir ~state_home:dir () |> ok_or_failwith in
    f world runner store)
;;

let json_set json key value =
  match json with
  | `Assoc fields ->
    `Assoc ((key, value) :: List.Assoc.remove fields ~equal:String.equal key)
  | _ -> failwith "expected an object"
;;

let replace_persisted_mode path ~embedded mode =
  let json = Yojson.Safe.from_string (In_channel.read_all path) in
  let json =
    if embedded
    then
      json_set
        json
        "config"
        (json_set (Yojson.Safe.Util.member "config" json) "mode" (`String mode))
    else json_set json "mode" (`String mode)
  in
  Out_channel.write_all path ~data:(Yojson.Safe.to_string json)
;;

let schedule_fixture world runner =
  configure runner ~mode:Autonomy.Mode.Live ~grace_seconds:100 ~persistence_seconds:10 ();
  List.iter [ 0; 1; 11 ] ~f:(fun seconds ->
    world.now_ref := at seconds;
    ignore (tick runner : Runner.tick_result));
  assert (List.length (status runner).active = 1)
;;

let%test_unit "configure live after a migration status read always starts a new cycle" =
  List.iter
    [ true, false; false, true; true, true ]
    ~f:(fun (legacy_policy, legacy_state) ->
      with_world_store ~f:(fun world runner store ->
        schedule_fixture world runner;
        if legacy_policy
        then replace_persisted_mode (Store.policy_path store) ~embedded:false "dry-run";
        if legacy_state
        then replace_persisted_mode (Store.state_path store) ~embedded:true "dry_run";
        world.now_ref := at 10000;
        assert (List.is_empty (status runner).active);
        (* Loading status must not erase the evidence needed by configure. *)
        configure runner ~mode:Autonomy.Mode.Live ();
        assert (is_cancelled (outcome_of runner ~id:"act-1"));
        ignore (tick runner : Runner.tick_result);
        assert (List.is_empty (status runner).active);
        assert (List.is_empty (get world.closed_ref));
        world.now_ref := at 10001;
        ignore (tick runner : Runner.tick_result);
        world.now_ref := at 10011;
        ignore (tick runner : Runner.tick_result);
        let pending = List.hd_exn (status runner).active in
        assert (String.equal pending.id "act-2");
        [%test_eq: Time_ns.t] pending.deadline (at 10111);
        assert (List.is_empty (get world.closed_ref));
        world.now_ref := at 10111;
        ignore (tick runner : Runner.tick_result);
        assert (is_fired (outcome_of runner ~id:"act-2"));
        [%test_eq: string list] (get world.closed_ref) [ "@2" ]))
;;

let%test_unit "off migration persists cancellations before canonicalizing the policy" =
  with_world_store ~f:(fun world runner store ->
    schedule_fixture world runner;
    replace_persisted_mode (Store.policy_path store) ~embedded:false "dryrun";
    world.now_ref := at 10000;
    let before = get world.observed_count in
    (match tick runner with
     | Runner.Skipped _ -> ()
     | _ -> failwith "legacy policy should become off");
    assert (get world.observed_count = before);
    let policy =
      Yojson.Safe.from_string (In_channel.read_all (Store.policy_path store))
    in
    [%test_eq: string] Yojson.Safe.Util.(member "mode" policy |> to_string) "off";
    let state = Store.load_state ~now:(at 10001) store |> ok_or_failwith in
    assert (List.is_empty state.active && Map.is_empty state.candidates);
    assert (state.next_action_id = 2);
    assert (is_cancelled (outcome_of runner ~id:"act-1"));
    let audit_before = In_channel.read_all (Store.audit_path store) in
    ignore (tick runner : Runner.tick_result);
    [%test_eq: string] (In_channel.read_all (Store.audit_path store)) audit_before;
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "paused legacy policy remains paused when explicitly configured live" =
  with_world_store ~f:(fun world runner store ->
    schedule_fixture world runner;
    ok_or_failwith (await (Runner.pause runner));
    replace_persisted_mode (Store.policy_path store) ~embedded:false "dry-run";
    replace_persisted_mode (Store.state_path store) ~embedded:true "dry-run";
    world.now_ref := at 10000;
    configure runner ~mode:Autonomy.Mode.Live ();
    assert (status runner).paused;
    (match tick runner with
     | Runner.Skipped _ -> ()
     | _ -> failwith "pause was lost during migration");
    ok_or_failwith (await (Runner.resume runner));
    ignore (tick runner : Runner.tick_result);
    assert (List.is_empty (status runner).active);
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "migration fails closed without rewriting a corrupt state or its policy" =
  with_world_store ~f:(fun world runner store ->
    schedule_fixture world runner;
    replace_persisted_mode (Store.policy_path store) ~embedded:false "dry-run";
    let policy = In_channel.read_all (Store.policy_path store) in
    Out_channel.write_all (Store.state_path store) ~data:"{broken";
    assert (Result.is_error (await (Runner.configure runner ~mode:Autonomy.Mode.Live ())));
    assert (Result.is_error (await (Runner.tick runner)));
    [%test_eq: string] (In_channel.read_all (Store.policy_path store)) policy;
    [%test_eq: string] (In_channel.read_all (Store.state_path store)) "{broken";
    assert (List.is_empty (get world.closed_ref)))
;;

let%test_unit "invalid timing changes preserve the previous policy and pending work" =
  with_world_store ~f:(fun world runner store ->
    schedule_fixture world runner;
    let policy = In_channel.read_all (Store.policy_path store) in
    let state = In_channel.read_all (Store.state_path store) in
    assert (Result.is_error (await (Runner.configure runner ~grace_seconds:(-1) ())));
    assert (Result.is_error (await (Runner.configure runner ~persistence_seconds:(-1) ())));
    [%test_eq: string] (In_channel.read_all (Store.policy_path store)) policy;
    [%test_eq: string] (In_channel.read_all (Store.state_path store)) state;
    assert (List.length (status runner).active = 1))
;;
