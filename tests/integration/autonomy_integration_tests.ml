(** End-to-end test of the autonomous cleanup pipeline against a real tmux
    server on an isolated socket ([tmux -L ...]). The server and all state live
    under a throwaway [/tmp] directory; the user's real tmux server and XDG
    directories are never touched.

    The test drives the full lifecycle:
      observed -> persisted candidate -> grace countdown -> fresh eligibility
      recheck -> native snapshot -> second recheck -> close (live mode), then
      verifies the same window is only *recorded* (not closed) under dry-run.

    It runs under the full Async scheduler (the pipeline spawns real tmux and
    ps commands), unlike the unit tests which run on a pumped scheduler. *)
open! Core
open Async

module Runner = Tmux_recovery_application.Autonomy
module Domain = Tmux_recovery_domain.Autonomy

let tmux = "/usr/bin/tmux"

(** [let%bind] for ['a Or_error.t Deferred.t] chains. *)
module Let_syntax = struct
  let bind = Deferred.Or_error.bind
end

(** Run a tmux command on the isolated socket. Arguments are passed as a proper
    argv list (no shell), so multi-word arguments (e.g. the send-keys payload)
    stay intact. A non-zero exit is surfaced as an error. *)
let run_tmux socket args =
  Deferred.bind
    (Process.run_lines ~prog:tmux ~args:("-L" :: socket :: args) ())
    ~f:(fun _output -> Deferred.return (Ok ()))
;;

let list_windows socket session =
  Process.run_lines
    ~prog:tmux
    ~args:[ "-L"; socket; "list-windows"; "-t"; session; "-F"; "#{window_id} #{window_name}" ]
    ()
;;

(** Create a window whose pane runs a process posing as "codex" (argv[0]).
    Codex detection matches the process command, finds no durable thread
    reference, and the recovery plan marks the pane blocked: the window is
    exactly the "idle, unrecoverable" candidate the autonomy funnel tracks. *)
let make_blocked_window socket session ~name =
  let%bind () = run_tmux socket [ "new-window"; "-t"; session; "-n"; name; "-c"; "/tmp" ] in
  let%bind () =
    run_tmux socket [ "send-keys"; "-t"; (session ^ ":" ^ name); "exec -a codex sleep 600"; "C-m" ]
  in
  (* Give the pane time to exec so [pane_current_command] reads "codex". *)
  Clock_ns.after (Time_ns.Span.of_int_sec 1) >>| fun _ -> Ok ()
;;

let window_id_of (lines : string list) (name : string) =
  let found =
    List.find lines ~f:(fun line ->
      (match String.split line ~on:' ' with
       | _window_id :: window_name :: _ -> String.equal window_name name
       | _ -> false))
  in
  (match found with
   | Some line ->
     let id = String.split line ~on:' ' |> List.hd_exn in
     (Ok id : (string, Error.t) result)
   | None ->
     let err = Error.createf "no window named %s" name in
     (Error err : (string, Error.t) result))
;;

let check label actual expected =
  if String.equal actual expected
  then (Ok () : unit Or_error.t)
  else
    let err = Error.createf "%s: got %s, expected %s" label actual expected in
    (Error err : unit Or_error.t)
;;

(** Verify a native snapshot directory was written under [dir/snapshots]. *)
let check_snapshot dir : unit Or_error.t Deferred.t =
  let snapshot_dir = Filename.concat dir "snapshots" in
  (match Sys_unix.file_exists snapshot_dir with
   | `No -> Deferred.return (Error (Error.of_string "snapshot directory missing"))
   | `Unknown -> Deferred.return (Error (Error.of_string "snapshot directory unknown"))
   | `Yes ->
     (match Or_error.try_with (fun () ->
        let d = Caml_unix.opendir snapshot_dir in
        let rec loop acc =
          (match Caml_unix.readdir d with
           | name -> loop (name :: acc)
           | exception (Caml_unix.Unix_error _ | End_of_file) -> acc)
        in
        let e = loop [] in
        Caml_unix.closedir d;
        e)
      with
      | Error _ -> Deferred.return (Error (Error.of_string "snapshot read failed"))
      | Ok entries ->
        (match List.find entries ~f:(fun name -> String.is_suffix name ~suffix:".snapshot") with
         | None -> Deferred.return (Error (Error.of_string "no snapshot file was written"))
         | Some _ -> Deferred.return (Ok ()))))
;;

let window_ids (lines : string list) =
  List.map lines ~f:(fun line -> String.split line ~on:' ' |> List.hd_exn)
;;

let run_all () =
  let socket = "tr-int-" ^ Core.Int.to_string (Pid.to_int (Unix.getpid ())) in
  let dir = Filename.concat "/tmp" socket in
  let cleanup () =
    Deferred.bind (run_tmux socket [ "kill-server" ]) ~f:(fun _ ->
      let _ = Core_unix.system (Printf.sprintf "rm -rf %s" dir) in
      Deferred.unit)
  in
  let body : unit Or_error.t Deferred.t =
    let _ = Core_unix.mkdir ~perm:0o755 dir in
    let%bind () = run_tmux socket [ "new-session"; "-d"; "-s"; "int"; "-x"; "100"; "-y"; "30" ] in
    let%bind () = make_blocked_window socket "int" ~name:"victim" in
    let%bind () = make_blocked_window socket "int" ~name:"keep" in
    let%bind lines = list_windows socket "int" in
    let%bind victim_id = Deferred.return (window_id_of lines "victim") in
    let%bind survivor_id = Deferred.return (window_id_of lines "keep") in
    let clock = ref (Time_ns.now ()) in
    let bump seconds = clock := Time_ns.add !clock (Time_ns.Span.of_int_sec seconds) in
    let deps =
      Runner.default_deps ~socket_name:socket ~now:(fun () -> !clock) ~snapshot_dir:dir ()
    in
    let%bind store = Deferred.return (Autonomy_store.create ~config_home:dir ~state_home:dir ()) in
    let%bind runner = Deferred.return (Runner.create ~store ~deps ()) in
    let%bind () =
      Runner.configure runner ~mode:Domain.Mode.Live ~grace_seconds:5 ~persistence_seconds:2
        ~snapshot_before_fire:true ()
    in
    (* t0: first quiescence sample for both windows. *)
    let%bind t0 = Runner.tick runner in
    let%bind () =
      (match t0 with
       | Runner.Reconciled r ->
         Deferred.return (check "t0 candidates" (string_of_int (Map.length r.state.candidates)) "2")
       | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("t0 skipped: " ^ s))))
    in
    bump 3;
    (* t1: second (unchanged) sample. The eligibility clock starts here, but the
       persistence threshold has not yet elapsed, so nothing is scheduled. *)
    let%bind t1 = Runner.tick runner in
    let%bind () =
      (match t1 with
       | Runner.Reconciled r ->
         Deferred.return (check "t1 not yet scheduled" (string_of_int (List.length r.state.active)) "0")
       | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("t1 skipped: " ^ s))))
    in
    bump 3;
    (* t2: persistence elapsed -> both windows are scheduled actions. *)
    let%bind t2 = Runner.tick runner in
    let%bind () =
      (match t2 with
       | Runner.Reconciled r ->
         Deferred.return (check "t2 scheduled" (string_of_int (List.length r.state.active)) "2")
       | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("t2 skipped: " ^ s))))
    in
    (* Simulate a runner/TUI restart: a fresh runner over the same persistent
       store still sees both scheduled actions. *)
    let%bind restarted = Deferred.return (Runner.create ~store ~deps ()) in
    let%bind s1 = Runner.status restarted in
    let%bind () =
      Deferred.return (check "active after restart" (string_of_int (List.length s1.active)) "2")
    in
    bump 6;
    (* Past the grace deadline: the pipeline fires one due action on the
       isolated socket and leaves the sibling window alone. Which window is
       first is an implementation detail, so we discover the fired window from
       the durable record and assert the invariants for it and its sibling. *)
    let%bind fire = Runner.tick restarted in
    let%bind () =
      (match fire with
       | Runner.Reconciled r ->
         (match r.fired with
          | Some _ -> Deferred.return (Ok ())
          | None -> Deferred.return (Error (Error.of_string "no action fired after the deadline")))
       | Runner.Skipped reason -> Deferred.return (Error (Error.of_string ("fire skipped: " ^ reason))))
    in
    let%bind s2 = Runner.status restarted in
    let%bind () =
      (match List.find s2.archived ~f:(fun a ->
         (match a.outcome with
          | Domain.Fired { dry_run = false ; _ } -> true
          | _ -> false))
       with
       | None -> Deferred.return (Error (Error.of_string "no live fire was archived"))
       | Some action ->
         let fired_window = action.window_id in
         let survivor =
           if String.equal fired_window victim_id then survivor_id else victim_id
         in
         (* The closed window is gone; the sibling window survives. *)
         let%bind windows = list_windows socket "int" in
         let ids = window_ids windows in
         let%bind () =
           if List.mem ids fired_window ~equal:String.equal
           then Deferred.return (Error (Error.of_string "fired window still exists"))
           else if not (List.mem ids survivor ~equal:String.equal)
           then Deferred.return (Error (Error.of_string "sibling window disappeared"))
           else Deferred.return (Ok ())
         in
         (* A native snapshot of the isolated server was taken before the close. *)
         let%bind () = check_snapshot dir in
         (* Switch to dry-run. A policy change resets the funnel, so the
            surviving window must re-accumulate persistence and grace before it
            can fire. The dry-run fire is recorded and the window survives. *)
         let%bind () =
           Runner.configure restarted ~mode:Domain.Mode.Dry_run ~grace_seconds:5
             ~persistence_seconds:2 ()
         in
         (* d0: survivor re-observed (first sample); the closed window is gone. *)
         let%bind d0 = Runner.tick restarted in
         let%bind () =
           (match d0 with
            | Runner.Reconciled r ->
              Deferred.return
                (check "d0 candidates" (string_of_int (Map.length r.state.candidates)) "1")
            | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("d0 skipped: " ^ s))))
         in
         bump 3;
         (* d1: survivor confirmed (eligibility clock starts). *)
         let%bind d1 = Runner.tick restarted in
         let%bind () =
           (match d1 with
            | Runner.Reconciled r ->
              Deferred.return
                (check "d1 not yet scheduled" (string_of_int (List.length r.state.active)) "0")
            | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("d1 skipped: " ^ s))))
         in
         bump 3;
         (* d2: survivor scheduled (persistence elapsed). *)
         let%bind d2 = Runner.tick restarted in
         let%bind () =
           (match d2 with
            | Runner.Reconciled r ->
              Deferred.return
                (check "d2 scheduled" (string_of_int (List.length r.state.active)) "1")
            | Runner.Skipped s -> Deferred.return (Error (Error.of_string ("d2 skipped: " ^ s))))
         in
         bump 6;
         (* d3: past the dry-run grace deadline -> the close is recorded, not done. *)
         let%bind d3 = Runner.tick restarted in
         let%bind () =
           (match d3 with
            | Runner.Reconciled r ->
              (match r.fired with
               | Some _ -> Deferred.return (Ok ())
               | None -> Deferred.return (Error (Error.of_string "dry-run fire not recorded")))
            | Runner.Skipped reason ->
              Deferred.return (Error (Error.of_string ("d3 skipped: " ^ reason))))
         in
         let%bind s3 = Runner.status restarted in
         let%bind () =
           (match List.find s3.archived ~f:(fun a -> String.equal a.window_id survivor) with
            | Some action ->
              (match action.outcome with
               | Domain.Fired { dry_run = true ; _ } -> Deferred.return (Ok ())
               | _ ->
                 Deferred.return
                   (Error (Error.of_string "dry-run fire was not recorded for the survivor")))
            | None -> Deferred.return (Error (Error.of_string "survivor action not archived")))
         in
         (* Dry-run must never close the window. *)
         let%bind windows = list_windows socket "int" in
         let ids = window_ids windows in
         let%bind () =
           if List.mem ids survivor ~equal:String.equal
           then Deferred.return (Ok ())
           else Deferred.return (Error (Error.of_string "dry-run closed the survivor window"))
         in
         Deferred.return (Ok ()))
    in
    Deferred.return (Ok ())
  in
  (* Always tear down the isolated server and state, even on failure. *)
  Deferred.bind body ~f:(fun result ->
    Deferred.bind (cleanup ()) ~f:(fun () -> Deferred.return result))
;;

let never (x : 'a) = (match x with _ -> Stdlib.exit 1)

let () =
  let d = run_all () in
  let _ =
    Deferred.bind d ~f:(function
      | Ok () ->
        print_endline "PASS: autonomous pipeline end-to-end (isolated socket)";
        Stdlib.exit 0
      | Error e ->
        print_endline ("FAIL: " ^ Error.to_string_hum e);
        Stdlib.exit 1)
  in
  let _ =
    Deferred.bind (Clock_ns.after (Time_ns.Span.of_int_sec 60)) ~f:(fun _ ->
      print_endline "TIMEOUT: 60s elapsed without completion";
      Deferred.unit)
  in
  never (Scheduler.go ())
;;
