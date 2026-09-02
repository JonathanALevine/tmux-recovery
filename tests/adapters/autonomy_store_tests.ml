open! Core

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
    let unlink path = (try Core_unix.unlink path with Caml_unix.Unix_error _ -> ()) in
    let rmdir path = (try Core_unix.rmdir path with Caml_unix.Unix_error _ -> ()) in
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
    Or_error.bind (Or_error.try_with (fun () -> Core_unix.mkdir ~perm:0o700 base)) ~f:(fun () ->
      (match Autonomy_store.create ~config_home ~state_home () with
       | Ok store ->
         let r = f store in
         cleanup ();
         r
       | Error _ as error ->
         cleanup ();
         error))
  in
  result
;;

let test_create_and_policy () =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.load_policy store) ~f:(fun config ->
        (match Autonomy.Mode.equal config.mode Autonomy.Mode.Dry_run with
         | true ->
           Or_error.bind
             (Autonomy_store.save_policy store live_config)
             ~f:(fun () -> Autonomy_store.load_policy store)
         | false -> Or_error.error_string "expected default dry-run policy"))
    )
  in
  let result = Or_error.map result ~f:(fun config -> Autonomy.equal_config config live_config) in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let test_state_default_and_round_trip () =
  let result =
    with_temp_store (fun store ->
      let state = Autonomy.empty ~config:live_config in
      Or_error.bind (Autonomy_store.save_state store state) ~f:(fun () ->
        Or_error.bind (Autonomy_store.load_state store) ~f:(fun restored ->
          Ok (Autonomy.equal_state restored state))))
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let test_state_missing_uses_policy () =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.save_policy store live_config) ~f:(fun () ->
        Or_error.bind (Autonomy_store.load_state store) ~f:(fun state ->
          Ok (Autonomy.equal_config state.config live_config))))
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let test_state_corrupt_fails_closed () =
  let result =
    with_temp_store (fun store ->
      Out_channel.with_file (Autonomy_store.state_path store) ~f:(fun oc ->
        Out_channel.output_string oc "not json {");
      (match Autonomy_store.load_state store with
       | Error _ -> Ok ()
       | Ok _ -> Or_error.error_string "corrupt state must fail closed"))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let test_policy_corrupt_fails () =
  let result =
    with_temp_store (fun store ->
      Out_channel.with_file (Autonomy_store.policy_path store) ~f:(fun oc ->
        Out_channel.output_string oc "garbage");
      (match Autonomy_store.load_policy store with
       | Error _ -> Ok ()
       | Ok _ -> Or_error.error_string "corrupt policy must be an error"))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;

let test_audit_round_trip_and_dedup () =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.sync_audit store [sample_entry]) ~f:(fun () ->
        Or_error.bind (Autonomy_store.sync_audit store [sample_entry]) ~f:(fun () ->
          Or_error.bind (Autonomy_store.sync_audit store [other_entry; sample_entry]) ~f:(fun () ->
            Autonomy_store.read_audit store))))
  in
  let result =
    Or_error.map result ~f:(fun entries ->
      let sorted = List.sort entries ~compare:(fun a b -> Time_ns.compare a.at b.at) in
      (match sorted with
       | [e1; e2] ->
         (Autonomy.Audit_event.equal e1.event sample_entry.event)
         && (Autonomy.Audit_event.equal e2.event other_entry.event)
         && String.equal e2.detail other_entry.detail
       | _ -> false))
  in
  [%test_eq: bool Or_error.t] result (Ok true)
;;

let test_audit_skips_corrupt_lines () =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.sync_audit store [sample_entry]) ~f:(fun () ->
        let fd =
          Caml_unix.openfile
            (Autonomy_store.audit_path store)
            [Caml_unix.O_WRONLY; Caml_unix.O_APPEND; Caml_unix.O_CREAT]
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

let test_with_lock_serializes () =
  let result =
    with_temp_store (fun store ->
      Or_error.bind (Autonomy_store.with_lock store ~f:(fun () -> Ok ())) ~f:(fun () ->
        Autonomy_store.with_lock store ~f:(fun () -> Ok ())))
  in
  [%test_eq: unit Or_error.t] result (Ok ())
;;
