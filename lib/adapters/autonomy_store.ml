(** Durable storage for the autonomous cleanup pipeline.

    Layout (under the XDG directories):

    - [config_home/tmux-recovery/autonomy.json]       -- the user's policy
    - [state_home/tmux-recovery/autonomy-state.json]  -- the engine state
    - [state_home/tmux-recovery/autonomy-audit.jsonl] -- durable audit log
    - [state_home/tmux-recovery/autonomy.lock]        -- advisory lock (flock)

    Writes are atomic (temp file + fsync + rename). The engine state is
    fail-closed: a corrupt or unreadable state file is an error and never
    leads to a window being closed. The lock serializes reconcile/fire
    transactions between the runner, the CLI, and the TUI. *)

open! Core
open Async

module Autonomy = Tmux_recovery_domain.Autonomy

type t =
  { config_home : string
  ; state_home : string
  }

let policy_dir (t : t) = Filename.concat t.config_home "tmux-recovery"
let state_dir (t : t) = Filename.concat t.state_home "tmux-recovery"

let policy_path (t : t) = Filename.concat (policy_dir t) "autonomy.json"
let state_path (t : t) = Filename.concat (state_dir t) "autonomy-state.json"
let audit_path (t : t) = Filename.concat (state_dir t) "autonomy-audit.jsonl"
let lock_path (t : t) = Filename.concat (state_dir t) "autonomy.lock"

let create ?config_home ?state_home () =
  let open Or_error.Let_syntax in
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let config_home =
    config_home
    |> Option.value ~default:(
      Sys.getenv "XDG_CONFIG_HOME"
      |> Option.value ~default:(Filename.concat home ".config"))
  in
  let state_home =
    state_home
    |> Option.value ~default:(
      Sys.getenv "XDG_STATE_HOME"
      |> Option.value ~default:(Filename.concat home ".local/state"))
  in
  let t = { config_home; state_home } in
  let%bind () = Or_error.try_with (fun () -> Core_unix.mkdir_p ~perm:0o700 (policy_dir t)) in
  let%bind () = Or_error.try_with (fun () -> Core_unix.mkdir_p ~perm:0o700 (state_dir t)) in
  return t
;;

let atomic_write path contents =
  let dir = Filename.dirname path in
  let tmp =
    Filename.concat dir (Filename.basename path ^ ".tmp-" ^ Int.to_string (Pid.to_int (Core_unix.getpid ())))
  in
  Or_error.try_with (fun () ->
    (match Sys_unix.file_exists tmp with
     | `Yes -> Core_unix.unlink tmp
     | `No | `Unknown -> ());
    let ic = Core_unix.openfile tmp ~mode:[O_WRONLY; O_CREAT; O_TRUNC; O_CLOEXEC] ~perm:0o600 in
    let buf = Bytes.of_string contents in
    let len = Bytes.length buf in
    let offset = ref 0 in
    while !offset < len do
      let n = Caml_unix.write ic buf !offset (len - !offset) in
      offset := !offset + n
    done;
    Caml_unix.fsync ic;
    Caml_unix.close ic;
    Core_unix.rename ~src:tmp ~dst:path;
    ())
;;

let read_file path = Or_error.try_with (fun () -> In_channel.read_all path)

let file_exists path =
  match Sys_unix.file_exists path with
  | `Yes -> true
  | `No | `Unknown -> false
;;

let with_lock t ~f =
  let fd =
    Core_unix.openfile (lock_path t) ~mode:[O_RDWR; O_CREAT; O_CLOEXEC] ~perm:0o600
  in
  Exn.protect
    ~f:(fun () ->
      Core_unix.lockf fd ~mode:Core_unix.F_LOCK ~len:0L;
      Exn.protect ~f ~finally:(fun () -> Core_unix.lockf fd ~mode:Core_unix.F_ULOCK ~len:0L))
    ~finally:(fun () -> Caml_unix.close fd)
;;

let load_policy (t : t) =
  let open Or_error.Let_syntax in
  let path = policy_path t in
  if not (file_exists path)
  then return Autonomy.default_config
  else (
    let%bind contents = read_file path in
    (match Yojson.Safe.from_string contents with
     | exception Yojson.Json_error _ ->
       Or_error.error_s [%message "corrupt policy file; refusing to run" path]
     | json ->
       (match Autonomy.config_of_yojson json with
        | Error e -> Error (Error.tag e ~tag:([%string "invalid policy file %{path}"]))
        | Ok config -> Ok config)))
;;

let save_policy (t : t) config =
  atomic_write (policy_path t) (Yojson.Safe.to_string (Autonomy.config_to_yojson config))
;;

let load_state (t : t) =
  let open Or_error.Let_syntax in
  let path = state_path t in
  if not (file_exists path)
  then (
    let%map config = load_policy t in Autonomy.empty ~config)
  else (
    let%bind contents = read_file path in
    (match Yojson.Safe.from_string contents with
     | exception Yojson.Json_error _ ->
       Or_error.error_s
         [%message
           "corrupt autonomy state file; refusing to run (fail-closed). Delete the file to \
            reset the engine."
           path]
     | json ->
       (match Autonomy.state_of_yojson json with
        | Error _ ->
          Or_error.error_s
            [%message
              "invalid autonomy state file; refusing to run (fail-closed). Delete the file to \
               reset the engine."
              path]
        | Ok state -> Ok state)))
;;

let save_state (t : t) state =
  atomic_write (state_path t) (Yojson.Safe.to_string (Autonomy.state_to_yojson state))
;;

module Audit = struct
  type line =
    { seq : int
    ; entry : Autonomy.audit_entry
    }

  let event_label = function
    | Autonomy.Audit_event.Scheduled -> "scheduled"
    | Autonomy.Audit_event.Fired -> "fired"
    | Autonomy.Audit_event.Cancelled -> "cancelled"
    | Autonomy.Audit_event.Aborted -> "aborted"
    | Autonomy.Audit_event.Failed -> "failed"
    | Autonomy.Audit_event.Paused -> "paused"
    | Autonomy.Audit_event.Resumed -> "resumed"
    | Autonomy.Audit_event.Policy_changed -> "policy_changed"
  ;;

  let event_of_label = function
    | "scheduled" -> Ok Autonomy.Audit_event.Scheduled
    | "fired" -> Ok Autonomy.Audit_event.Fired
    | "cancelled" -> Ok Autonomy.Audit_event.Cancelled
    | "aborted" -> Ok Autonomy.Audit_event.Aborted
    | "failed" -> Ok Autonomy.Audit_event.Failed
    | "paused" -> Ok Autonomy.Audit_event.Paused
    | "resumed" -> Ok Autonomy.Audit_event.Resumed
    | "policy_changed" -> Ok Autonomy.Audit_event.Policy_changed
    | other -> Or_error.error_s [%message "bad audit event" other]
  ;;

  let key (entry : Autonomy.audit_entry) =
    String.concat
      ~sep:"|"
      [ Time_ns.to_string_utc entry.at
      ; event_label entry.event
      ; (match entry.action_id with Some id -> id | None -> "")
      ; (match entry.window_id with Some id -> id | None -> "")
      ; entry.detail
      ]
  ;;

  let to_yojson line =
    `Assoc
      [ "seq", `Int line.seq
      ; "at", `String (Time_ns.to_string_utc line.entry.at)
      ; "event", `String (event_label line.entry.event)
      ; "action_id", (match line.entry.action_id with Some id -> `String id | None -> `Null)
      ; "window_id", (match line.entry.window_id with Some id -> `String id | None -> `Null)
      ; "detail", `String line.entry.detail
      ]
  ;;

  let of_yojson (json : Yojson.Safe.t) =
    let open Or_error.Let_syntax in
    let open Yojson.Safe.Util in
    let%bind seq =
      (match member "seq" json |> to_int with
       | n when n >= 1 -> Ok n
       | _ -> Or_error.error_string "bad audit seq")
    in
    let%bind at =
      Or_error.try_with (fun () -> Time_ns.of_string_with_utc_offset (to_string (member "at" json)))
    in
    let%bind event = event_of_label (to_string (member "event" json)) in
    let action_id =
      (match member "action_id" json with `Null -> None | v -> Some (to_string v))
    in
    let window_id =
      (match member "window_id" json with `Null -> None | v -> Some (to_string v))
    in
    let detail = to_string (member "detail" json) in
    return { seq; entry = { at; event; action_id; window_id; detail } }
  ;;

  let read_all (t : t) : line list Or_error.t =
    let open Or_error.Let_syntax in
    let path = audit_path t in
    if not (file_exists path)
    then return []
    else (
      let%bind contents = read_file path in
      let lines =
        String.split contents ~on:'\n'
        |> List.filter ~f:(fun s -> not (String.is_empty s))
        |> List.filter_map ~f:(fun line ->
          (try Some (Yojson.Safe.from_string line |> of_yojson |> Or_error.ok_exn) with
           | Yojson.Json_error _ | Failure _ -> None))
      in
      (* Keep the latest line per seq. *)
      let by_seq =
        List.fold lines ~init:Int.Map.empty ~f:(fun acc line ->
          Map.set acc ~key:line.seq ~data:line)
      in
      return (Map.data by_seq))
  ;;

  let sync (t : t) (entries : Autonomy.audit_entry list) =
    let open Or_error.Let_syntax in
    let%bind existing = read_all t in
    let existing_keys = existing |> List.map ~f:(fun l -> key l.entry) |> String.Set.of_list in
    let next_seq =
      List.fold existing ~init:0 ~f:(fun acc l -> if l.seq > acc then l.seq else acc)
    in
    let fresh =
      List.filter entries ~f:(fun entry -> not (Set.mem existing_keys (key entry)))
    in
    (match fresh with
     | [] -> return ()
     | entries ->
       let lines =
         List.mapi entries ~f:(fun i entry -> { seq = next_seq + i + 1; entry })
       in
       let%bind () =
         Or_error.try_with (fun () ->
           let ic =
             Core_unix.openfile
               (audit_path t)
               ~mode:[O_WRONLY; O_CREAT; O_APPEND; O_CLOEXEC]
               ~perm:0o600
           in
           List.iter lines ~f:(fun line ->
             let contents = Bytes.of_string (Yojson.Safe.to_string (to_yojson line) ^ "\n") in
             let n = Bytes.length contents in
             let written = ref 0 in
             while !written < n do
               let k = Caml_unix.write ic contents !written (n - !written) in
               written := !written + k
             done);
           Caml_unix.fsync ic;
           Caml_unix.close ic;
           ())
       in
       return ())
  ;;
end

let with_lock_async t ~f =
  let fd =
    Core_unix.openfile (lock_path t) ~mode:[O_RDWR; O_CREAT; O_CLOEXEC] ~perm:0o600
  in
  Monitor.protect
    (fun () ->
      Core_unix.lockf fd ~mode:Core_unix.F_LOCK ~len:0L;
      Monitor.protect (fun () -> f ()) ~finally:(fun () ->
        Core_unix.lockf fd ~mode:Core_unix.F_ULOCK ~len:0L;
        Deferred.unit))
    ~finally:(fun () ->
      Caml_unix.close fd;
      Deferred.unit)
;;

(** Idempotently append audit entries not already in the durable log. Safe to
    call repeatedly (e.g. after a crash between state save and audit append).
    Runs under the advisory lock. *)
let sync_audit t entries = with_lock t ~f:(fun () -> Audit.sync t entries)

(** Read the durable audit log, newest first. Corrupt lines are skipped. *)
let read_audit (t : t) =
  let open Or_error.Let_syntax in
  let%bind lines = Audit.read_all t in
  return (List.sort lines ~compare:(fun a b -> Int.compare b.seq a.seq) |> List.map ~f:(fun l -> l.entry))
