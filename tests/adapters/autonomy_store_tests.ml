open! Core
open Async
module Autonomy = Tmux_recovery_domain.Autonomy

let t0 = Time_ns.epoch
let at (seconds : int) = Time_ns.add t0 (Time_ns.Span.of_int_sec seconds)

let live_config : Autonomy.config =
  { mode = Autonomy.Mode.Live
  ; grace_seconds = 600
  ; persistence_seconds = 120
  ; snapshot_before_fire = true
  }
;;

let sample_entry =
  { Autonomy.at = at 5
  ; event = Autonomy.Audit_event.Scheduled
  ; action_id = Some "act-1"
  ; window_id = Some "@2"
  ; detail = "closes in 600s after persistence threshold"
  }
;;

let other_entry =
  { Autonomy.at = at 9
  ; event = Autonomy.Audit_event.Fired
  ; action_id = Some "act-1"
  ; window_id = Some "@2"
  ; detail = "closed"
  }
;;

let with_temp_store f =
  let base = "/tmp/tr-store-test-" ^ Int.to_string (Caml_unix.getpid ()) in
  let config_home = base ^ "/config" in
  let state_home = base ^ "/state" in
  let cleanup () =
    let unlink path =
      try Core_unix.unlink path with
      | Caml_unix.Unix_error _ -> ()
    in
    let rmdir path =
      try Core_unix.rmdir path with
      | Caml_unix.Unix_error _ -> ()
    in
    unlink (config_home ^ "/tmux-recovery/autonomy.json");
    unlink (state_home ^ "/tmux-recovery/autonomy-state.json");
    unlink (state_home ^ "/tmux-recovery/autonomy-audit.jsonl");
    unlink (state_home ^ "/tmux-recovery/autonomy.lock");
    rmdir (config_home ^ "/tmux-recovery");
    rmdir (state_home ^ "/tmux-recovery");
    rmdir config_home;
    rmdir state_home;
    rmdir base
  in
  let result =
    Or_error.bind
      (Or_error.try_with (fun () -> Core_unix.mkdir ~perm:0o700 base))
      ~f:(fun () ->
        match Autonomy_store.create ~config_home ~state_home () with
        | Ok store ->
          let r = f store in
          cleanup ();
          r
        | Error _ as error ->
          cleanup ();
          error)
  in
  result
;;

(** [held_lock path] reports whether this process currently holds an advisory
    (fcntl/[lockf]) lock on [path], by reading [/proc/locks] (Linux: each line is "<n>:
    TYPE ADVISORY READ|WRITE <pid> <major_hex>:<minor_hex>:<inode_dec> <start> <end>").
    Returns [None] where that interface is unavailable; the lock-state assertions in the
    tests then skip and the rest still runs. *)
let held_lock (path : string) : bool option =
  let locks_contents =
    match Sys_unix.file_exists "/proc/locks" with
    | `No | `Unknown -> None
    | `Yes ->
      (try Some (In_channel.read_all "/proc/locks") with
       | _ -> None)
  in
  match locks_contents with
  | None -> None
  | Some contents ->
    (match
       try Some (Core_unix.stat path) with
       | _ -> None
     with
     | None -> None
     | Some st ->
       let me = Int.to_string (Caml_unix.getpid ()) in
       let ino = Int.to_string st.st_ino in
       let line_holds (line : string) : bool =
         let fields =
           String.split line ~on:' ' |> List.filter ~f:(fun s -> not (String.is_empty s))
         in
         match List.nth fields 4, List.nth fields 5 with
         | Some pid, Some dev_ino ->
           (match String.split dev_ino ~on:':' |> List.last with
            | Some inode -> String.equal pid me && String.equal inode ino
            | None -> false)
         | _ -> false
       in
       Some (String.split contents ~on:'\n' |> List.exists ~f:line_holds))
;;

let run_cycles () = Async_kernel_scheduler.Expert.run_cycles_until_no_jobs_remain ()

exception Boom

let%test_unit "a fresh store defaults to off and the policy round-trips" =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.load_policy store) ~f:(fun config ->
        match Autonomy.Mode.equal config.mode Autonomy.Mode.Off with
        | true ->
          Or_error.bind (Autonomy_store.save_policy store live_config) ~f:(fun () ->
            Autonomy_store.load_policy store)
        | false -> Or_error.error_string "expected default off policy"))
  in
  let result =
    Or_error.map result ~f:(fun config -> Autonomy.equal_config config live_config)
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let%test_unit "engine state round-trips through the store" =
  let result =
    with_temp_store (fun store ->
      let state = Autonomy.empty ~config:live_config in
      Or_error.bind (Autonomy_store.save_state store state) ~f:(fun () ->
        Or_error.bind (Autonomy_store.load_state store) ~f:(fun restored ->
          Ok (Autonomy.equal_state restored state))))
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let%test_unit "a missing state file starts an empty engine with the current policy" =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.save_policy store live_config) ~f:(fun () ->
        Or_error.bind (Autonomy_store.load_state store) ~f:(fun state ->
          Ok (Autonomy.equal_config state.config live_config))))
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let%test_unit "a corrupt state file fails closed" =
  let result =
    with_temp_store (fun store ->
      Out_channel.with_file (Autonomy_store.state_path store) ~f:(fun oc ->
        Out_channel.output_string oc "not json {");
      match Autonomy_store.load_state store with
      | Error _ -> Ok ()
      | Ok _ -> Or_error.error_string "corrupt state must fail closed")
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "a corrupt policy file is an error" =
  let result =
    with_temp_store (fun store ->
      Out_channel.with_file (Autonomy_store.policy_path store) ~f:(fun oc ->
        Out_channel.output_string oc "garbage");
      match Autonomy_store.load_policy store with
      | Error _ -> Ok ()
      | Ok _ -> Or_error.error_string "corrupt policy must be an error")
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "audit sync is idempotent (dedup by entry identity)" =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.sync_audit store [ sample_entry ]) ~f:(fun () ->
        Or_error.bind (Autonomy_store.sync_audit store [ sample_entry ]) ~f:(fun () ->
          Or_error.bind
            (Autonomy_store.sync_audit store [ other_entry; sample_entry ])
            ~f:(fun () -> Autonomy_store.read_audit store))))
  in
  let result =
    Or_error.map result ~f:(fun entries ->
      let sorted = List.sort entries ~compare:(fun a b -> Time_ns.compare a.at b.at) in
      match sorted with
      | [ e1; e2 ] ->
        Autonomy.Audit_event.equal e1.event sample_entry.event
        && Autonomy.Audit_event.equal e2.event other_entry.event
        && String.equal e2.detail other_entry.detail
      | _ -> false)
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let%test_unit "corrupt audit lines are skipped on read" =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.sync_audit store [ sample_entry ]) ~f:(fun () ->
        let fd =
          Caml_unix.openfile
            (Autonomy_store.audit_path store)
            [ Caml_unix.O_WRONLY; Caml_unix.O_APPEND; Caml_unix.O_CREAT ]
            0o600
        in
        let broken = Bytes.of_string "{broken json\n" in
        let n = Caml_unix.write fd broken 0 (Bytes.length broken) in
        let _ = n in
        Caml_unix.close fd;
        Or_error.map (Autonomy_store.read_audit store) ~f:List.length))
  in
  [%test_eq: int Or_error.t] result (Ok 1)
;;

let%test_unit "with_lock acquires and releases the advisory lock" =
  let result =
    with_temp_store (fun store ->
      Or_error.bind
        (Autonomy_store.with_lock store ~f:(fun () -> Ok ()))
        ~f:(fun () -> Autonomy_store.with_lock store ~f:(fun () -> Ok ())))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "with_lock_async holds the lock until the deferred settles" =
  let result =
    with_temp_store (fun store ->
      let lock_file = Autonomy_store.lock_path store in
      let release_signal = Ivar.create () in
      let settled = Ivar.create () in
      let held_while_pending = ref None in
      let work =
        Monitor.try_with ~extract_exn:true (fun () ->
          Autonomy_store.with_lock_async store ~f:(fun () ->
            held_while_pending := held_lock lock_file;
            Ivar.read release_signal >>| fun () -> Ok ()))
      in
      let _ =
        Deferred.bind work ~f:(fun r ->
          Ivar.fill_exn settled r;
          Deferred.unit)
      in
      (* [f] is now pending on [release_signal]; the lock must still be held. *)
      Ivar.fill_exn release_signal ();
      run_cycles ();
      match Ivar.peek settled, !held_while_pending, held_lock lock_file with
      | Some (Ok (Ok ())), Some true, Some false -> Ok ()
      | Some (Ok (Ok ())), Some true, Some true ->
        Error (Error.of_string "the lock was not released after the deferred settled")
      | Some (Ok (Ok ())), Some true, None -> Ok () (* inconsistent observation; skip *)
      | Some (Ok (Ok ())), Some false, _ ->
        Error (Error.of_string "the lock was not held while the work was pending")
      | Some (Ok (Ok ())), None, _ -> Ok () (* non-Linux: lock state unobservable *)
      | Some (Ok (Error e)), _, _ -> Error e
      | Some (Error exn), _, _ -> Error (Error.of_string (Exn.to_string exn))
      | None, _, _ -> Error (Error.of_string "the locked work never settled"))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "with_lock_async releases the lock when the work raises" =
  let result =
    with_temp_store (fun store ->
      let lock_file = Autonomy_store.lock_path store in
      let boom = Ivar.create () in
      let settled = Ivar.create () in
      let work =
        Monitor.try_with ~extract_exn:true (fun () ->
          Autonomy_store.with_lock_async store ~f:(fun () ->
            Deferred.map (Ivar.read boom) ~f:(fun _ -> raise Boom)))
      in
      let _ =
        Deferred.bind work ~f:(fun r ->
          Ivar.fill_exn settled r;
          Deferred.unit)
      in
      Ivar.fill_exn boom ();
      run_cycles ();
      match Ivar.peek settled, held_lock lock_file with
      | Some (Error Boom), Some false -> Ok ()
      | Some (Error Boom), None -> Ok ()
      | Some (Error Boom), Some true ->
        Error (Error.of_string "the lock was not released after the error")
      | Some (Error exn), _ -> Error (Error.of_string (Exn.to_string exn))
      | Some (Ok _), _ -> Error (Error.of_string "the error did not propagate")
      | None, _ -> Error (Error.of_string "the locked work never settled"))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "sync_audit_unlocked appends entries from inside a held lock" =
  let result =
    with_temp_store (fun store ->
      Autonomy_store.with_lock store ~f:(fun () ->
        Or_error.bind
          (Autonomy_store.sync_audit_unlocked store [ sample_entry ])
          ~f:(fun () -> Or_error.map (Autonomy_store.read_audit store) ~f:List.length)))
  in
  [%test_eq: int Or_error.t] result (Ok 1)
;;

let json_set json key value =
  match json with
  | `Assoc fields ->
    `Assoc ((key, value) :: List.Assoc.remove fields ~equal:String.equal key)
  | _ -> failwith "expected an object"
;;

let scheduled_state () =
  let candidate : Autonomy.candidate =
    { target =
        { window_id = "@2"
        ; session_id = "$1"
        ; server_identity = "server"
        ; window_name = "exited"
        ; window_layout = "layout"
        ; panes = [ "%2", "codex" ]
        }
    ; reason = "unrecoverable"
    ; signature = "unchanged"
    }
  in
  List.fold
    [ 0; 1; 121 ]
    ~init:(Autonomy.empty ~config:live_config)
    ~f:(fun state seconds ->
      Autonomy.tick ~now:(at seconds) ~candidates:[ candidate ] state)
;;

let%test_unit "legacy policy resets schedules even when the embedded policy is live" =
  let result =
    with_temp_store (fun store ->
      let open Or_error.Let_syntax in
      let original =
        { (scheduled_state ()) with paused = true; paused_at = Some (at 122) }
      in
      let%bind () = Autonomy_store.save_state store original in
      let legacy =
        json_set (Autonomy.config_to_yojson live_config) "mode" (`String "dry-run")
      in
      let raw_policy = Yojson.Safe.to_string legacy in
      Out_channel.write_all (Autonomy_store.policy_path store) ~data:raw_policy;
      let%bind policy = Autonomy_store.load_policy store in
      let%bind migrated = Autonomy_store.load_state ~now:(at 10000) store in
      assert (Autonomy.Mode.equal policy.mode Autonomy.Mode.Off);
      assert (List.is_empty migrated.active && Map.is_empty migrated.candidates);
      assert (
        migrated.paused
        && Option.equal Time_ns.equal migrated.paused_at original.paused_at);
      assert (migrated.next_action_id = original.next_action_id);
      assert (List.length migrated.archived = 1);
      (* A status-only read preserves the raw migration input until it can be committed
         together with cancellation state under the transaction lock. *)
      assert (
        String.equal raw_policy (In_channel.read_all (Autonomy_store.policy_path store)));
      let%bind again = Autonomy_store.load_state ~now:(at 10001) store in
      assert (List.is_empty again.active);
      return ())
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "legacy embedded policy resets schedules even with an explicit live policy" =
  let result =
    with_temp_store (fun store ->
      let open Or_error.Let_syntax in
      let original = scheduled_state () in
      let%bind () = Autonomy_store.save_policy store live_config in
      let legacy =
        json_set
          (Autonomy.state_to_yojson original)
          "config"
          (json_set (Autonomy.config_to_yojson live_config) "mode" (`String "dry_run"))
      in
      Out_channel.write_all
        (Autonomy_store.state_path store)
        ~data:(Yojson.Safe.to_string legacy);
      let%bind state = Autonomy_store.load_state ~now:(at 10000) store in
      assert (List.is_empty state.active && Map.is_empty state.candidates);
      let%bind policy = Autonomy_store.load_policy store in
      assert (Autonomy.Mode.equal policy.mode Autonomy.Mode.Live);
      let live = Autonomy.with_config ~now:(at 10000) policy state in
      assert (List.is_empty (Autonomy.due ~now:(at 10000) live));
      return ())
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "normal explicit live and off policies preserve archived and paused state" =
  List.iter [ Autonomy.Mode.Live; Autonomy.Mode.Off ] ~f:(fun mode ->
    let result =
      with_temp_store (fun store ->
        let open Or_error.Let_syntax in
        let policy = { live_config with mode } in
        let original =
          scheduled_state ()
          |> Autonomy.pause ~now:(at 200)
          |> Autonomy.with_config ~now:(at 201) policy
        in
        let%bind () = Autonomy_store.save_policy store policy in
        let%bind () = Autonomy_store.save_state store original in
        let%map loaded = Autonomy_store.load_state ~now:(at 10000) store in
        [%test_eq: Autonomy.state] loaded original)
    in
    [%test_eq: unit Or_error.t] result (Ok ()))
;;

let%test_unit "legacy simulated audit is distinguished without rewriting or duplicating \
               history"
  =
  let result =
    with_temp_store (fun store ->
      let open Or_error.Let_syntax in
      let legacy_entry =
        { other_entry with detail = "dry-run; the window would be closed" }
      in
      let raw =
        Yojson.Safe.to_string
          (json_set (Autonomy.audit_entry_to_yojson legacy_entry) "seq" (`Int 1))
        ^ "\n"
      in
      Out_channel.write_all (Autonomy_store.audit_path store) ~data:raw;
      let%bind entries = Autonomy_store.read_audit store in
      (match entries with
       | [ entry ] -> [%test_eq: Autonomy.Audit_event.t] entry.event Legacy_simulated
       | _ -> failwith "history disappeared");
      let%bind () = Autonomy_store.sync_audit store entries in
      assert (String.equal raw (In_channel.read_all (Autonomy_store.audit_path store)));
      let%map entries = Autonomy_store.read_audit store in
      assert (List.length entries = 1))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let%test_unit "legacy policy cannot hide a corrupt or unreadable state" =
  let result =
    with_temp_store (fun store ->
      let legacy =
        json_set (Autonomy.config_to_yojson live_config) "mode" (`String "dryrun")
      in
      Out_channel.write_all
        (Autonomy_store.policy_path store)
        ~data:(Yojson.Safe.to_string legacy);
      Out_channel.write_all (Autonomy_store.state_path store) ~data:"{broken";
      assert (Result.is_error (Autonomy_store.load_state store));
      Core_unix.unlink (Autonomy_store.state_path store);
      Core_unix.mkdir (Autonomy_store.state_path store) ~perm:0o700;
      Exn.protect
        ~f:(fun () -> assert (Result.is_error (Autonomy_store.load_state store)))
        ~finally:(fun () -> Core_unix.rmdir (Autonomy_store.state_path store));
      Ok ())
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;
