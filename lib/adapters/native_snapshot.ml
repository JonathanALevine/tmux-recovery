open! Core
open Async
module Domain = Tmux_recovery_domain.Native_snapshot
module Snapshot = Tmux_recovery_domain.Snapshot

type config =
  { directory : string
  ; runtime_directory : string
  ; minimum_snapshots : int
  ; retention_days : int
  }

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let data_home =
    Sys.getenv "XDG_DATA_HOME"
    |> Option.value ~default:(Filename.concat home ".local/share")
  in
  let runtime_directory =
    Sys.getenv "XDG_RUNTIME_DIR"
    |> Option.first_some (Sys.getenv "TMPDIR")
    |> Option.value ~default:"/tmp"
    |> fun root -> Filename.concat root "tmux-recovery"
  in
  { directory = Filename.concat data_home "tmux-recovery/snapshots"
  ; runtime_directory
  ; minimum_snapshots = 5
  ; retention_days = 30
  }
;;

let snapshot_file directory id =
  Filename.concat (Filename.concat directory (Snapshot.Id.to_string id)) "snapshot.json"
;;

let hash_file directory id =
  Filename.concat (Filename.concat directory (Snapshot.Id.to_string id)) "SHA256SUM"
;;

let ensure_directory path = Core_unix.mkdir_p ~perm:0o700 path

let write_all fd contents =
  let rec loop position =
    if position < String.length contents
    then (
      let written =
        Core_unix.write_substring
          fd
          ~pos:position
          ~len:(String.length contents - position)
          ~buf:contents
      in
      if written = 0 then failwith "short write while committing snapshot";
      loop (position + written))
  in
  loop 0
;;

let write_file path contents =
  let fd =
    Core_unix.openfile path ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ] ~perm:0o600
  in
  Exn.protect
    ~f:(fun () ->
      write_all fd contents;
      Core_unix.fsync fd)
    ~finally:(fun () -> Core_unix.close fd)
;;

let fsync_directory directory =
  let fd = Core_unix.openfile directory ~mode:[ O_RDONLY; O_CLOEXEC ] in
  Exn.protect ~f:(fun () -> Core_unix.fsync fd) ~finally:(fun () -> Core_unix.close fd)
;;

let remove_temp directory =
  List.iter [ "snapshot.json"; "SHA256SUM" ] ~f:(fun name ->
    let path = Filename.concat directory name in
    match Sys_unix.file_exists path with
    | `Yes -> Core_unix.unlink path
    | `No | `Unknown -> ());
  match Sys_unix.is_directory directory with
  | `Yes -> Core_unix.rmdir directory
  | `No | `Unknown -> ()
;;

let pointer_id directory name =
  let path = Filename.concat directory name in
  match Sys_unix.is_symlink path with
  | `No -> Ok None
  | `Unknown -> Or_error.error_s [%message "could not inspect snapshot pointer" path]
  | `Yes ->
    Or_error.try_with (fun () -> Core_unix.readlink path)
    |> Or_error.bind ~f:(fun target ->
      if String.equal target (Filename.basename target)
      then Snapshot.Id.of_string target |> Or_error.map ~f:Option.some
      else
        Or_error.error_s [%message "snapshot pointer escapes its directory" path target])
;;

let replace_pointer directory name id =
  let final_path = Filename.concat directory name in
  let temporary_path =
    Filename.concat directory [%string ".%{name}.tmp-%{Core_unix.getpid ()#Pid}"]
  in
  (match Sys_unix.file_exists temporary_path with
   | `Yes -> Core_unix.unlink temporary_path
   | `No | `Unknown -> ());
  Core_unix.symlink ~target:(Snapshot.Id.to_string id) ~link_name:temporary_path;
  Core_unix.rename ~src:temporary_path ~dst:final_path
;;

let load_sync config id =
  match Snapshot.Id.kind id with
  | Resurrect -> Or_error.error_string "legacy snapshot IDs are not native bundles"
  | Native ->
    Or_error.try_with (fun () ->
      let contents = In_channel.read_all (snapshot_file config.directory id) in
      let expected_hash =
        In_channel.read_all (hash_file config.directory id) |> String.strip
      in
      let actual_hash = Sha256.digest_string contents in
      if not (String.equal expected_hash actual_hash)
      then
        failwithf
          "snapshot hash mismatch: expected %s but found %s"
          expected_hash
          actual_hash
          ();
      let snapshot =
        Yojson.Safe.from_string contents |> Domain.of_yojson |> Or_error.ok_exn
      in
      if not (Snapshot.Id.equal snapshot.id id)
      then failwith "snapshot directory and embedded ID differ";
      snapshot)
;;

let summary_of_snapshot config ~latest ~last_good (snapshot : Domain.t) =
  let snapshot_path = snapshot_file config.directory snapshot.Domain.id in
  let hash_path = hash_file config.directory snapshot.id in
  let size_bytes =
    Stdlib.Int64.add
      (Core_unix.stat snapshot_path).st_size
      (Core_unix.stat hash_path).st_size
  in
  { Snapshot.id = snapshot.id
  ; created_at = snapshot.created_at
  ; size_bytes
  ; latest
  ; last_good
  ; validity = Valid
  ; warnings = []
  ; session_count = Map.length snapshot.workspace.sessions
  ; window_count = Map.length snapshot.workspace.windows
  ; pane_count = Map.length snapshot.workspace.panes
  ; manifest = true
  ; legacy = false
  }
;;

let list_sync config =
  match Sys_unix.is_directory config.directory with
  | `No ->
    Ok
      { Snapshot.directory = config.directory
      ; directory_exists = false
      ; snapshots = []
      ; warnings = []
      }
  | `Unknown -> Or_error.error_string "could not inspect native snapshot directory"
  | `Yes ->
    let open Or_error.Let_syntax in
    let%bind latest = pointer_id config.directory "latest"
    and last_good = pointer_id config.directory "last-good" in
    let ids =
      Sys_unix.ls_dir config.directory
      |> List.filter_map ~f:(fun name ->
        Snapshot.Id.of_string name
        |> Result.ok
        |> Option.filter ~f:(fun id ->
          match Snapshot.Id.kind id with
          | Native -> true
          | Resurrect -> false))
    in
    let snapshots, warnings =
      List.fold ids ~init:([], []) ~f:(fun (summaries, warnings) id ->
        match load_sync config id with
        | Ok snapshot ->
          ( summary_of_snapshot
              config
              ~latest:(Option.exists latest ~f:(Snapshot.Id.equal id))
              ~last_good:(Option.exists last_good ~f:(Snapshot.Id.equal id))
              snapshot
            :: summaries
          , warnings )
        | Error error ->
          let path = snapshot_file config.directory id in
          let size_bytes =
            match Sys_unix.file_exists path with
            | `Yes -> (Core_unix.stat path).st_size
            | `No | `Unknown -> 0L
          in
          let created_at =
            match Sys_unix.file_exists path with
            | `Yes ->
              Core_unix.Ns_precision.stat path
              |> fun (stats : Core_unix.Ns_precision.stats) -> stats.st_mtime
            | `No | `Unknown -> Time_ns.epoch
          in
          ( { Snapshot.id
            ; created_at
            ; size_bytes
            ; latest = Option.exists latest ~f:(Snapshot.Id.equal id)
            ; last_good = Option.exists last_good ~f:(Snapshot.Id.equal id)
            ; validity = Invalid [ Error.to_string_hum error |> String.strip ]
            ; warnings = []
            ; session_count = 0
            ; window_count = 0
            ; pane_count = 0
            ; manifest = true
            ; legacy = false
            }
            :: summaries
          , [%string "could not validate %{Snapshot.Id.to_string id}"] :: warnings ))
    in
    Ok
      { Snapshot.directory = config.directory
      ; directory_exists = true
      ; snapshots = Snapshot.sort_newest_first snapshots
      ; warnings = List.rev warnings
      }
;;

let with_lock config ~socket_name f =
  ensure_directory config.runtime_directory;
  let socket = Option.value socket_name ~default:"default" in
  let lock_name = Sha256.digest_string socket |> fun digest -> String.prefix digest 16 in
  let path = Filename.concat config.runtime_directory (lock_name ^ ".lock") in
  let fd = Core_unix.openfile path ~mode:[ O_RDWR; O_CREAT; O_CLOEXEC ] ~perm:0o600 in
  Exn.protect
    ~f:(fun () ->
      Core_unix.lockf fd ~mode:F_LOCK ~len:0L;
      Exn.protect ~f ~finally:(fun () -> Core_unix.lockf fd ~mode:F_ULOCK ~len:0L))
    ~finally:(fun () -> Core_unix.close fd)
;;

let acquire_operation_lock config ~socket_name =
  In_thread.run (fun () ->
    Or_error.try_with (fun () ->
      ensure_directory config.runtime_directory;
      let socket = Option.value socket_name ~default:"default" in
      let lock_name =
        Sha256.digest_string socket |> fun digest -> String.prefix digest 16
      in
      let path = Filename.concat config.runtime_directory (lock_name ^ ".lock") in
      let fd = Core_unix.openfile path ~mode:[ O_RDWR; O_CREAT; O_CLOEXEC ] ~perm:0o600 in
      Core_unix.lockf fd ~mode:F_LOCK ~len:0L;
      fd))
;;

let release_operation_lock fd =
  In_thread.run (fun () ->
    Exn.protect
      ~f:(fun () -> Core_unix.lockf fd ~mode:F_ULOCK ~len:0L)
      ~finally:(fun () -> Core_unix.close fd))
;;

let with_operation_lock config ~socket_name f =
  let%bind acquired = acquire_operation_lock config ~socket_name in
  match acquired with
  | Error _ as error -> return error
  | Ok fd -> Monitor.protect f ~finally:(fun () -> release_operation_lock fd)
;;

let save_sync config ~socket_name (snapshot : Domain.t) =
  with_lock config ~socket_name (fun () ->
    ensure_directory config.directory;
    let id = snapshot.Domain.id in
    let final_directory = Filename.concat config.directory (Snapshot.Id.to_string id) in
    if Poly.equal (Sys_unix.file_exists final_directory) `Yes
    then failwith "native snapshot ID collision";
    let temporary_directory =
      Filename.concat
        config.directory
        [%string ".%{Snapshot.Id.to_string id}.tmp-%{Core_unix.getpid ()#Pid}"]
    in
    Core_unix.mkdir ~perm:0o700 temporary_directory;
    Exn.protect
      ~f:(fun () ->
        let contents = Domain.to_yojson snapshot |> Yojson.Safe.to_string in
        let hash = Sha256.digest_string contents in
        write_file (Filename.concat temporary_directory "snapshot.json") contents;
        write_file (Filename.concat temporary_directory "SHA256SUM") (hash ^ "\n");
        let temporary_config =
          { config with directory = Filename.dirname temporary_directory }
        in
        let temporary_id = id in
        let staged_file = Filename.concat temporary_directory "snapshot.json" in
        let staged_hash = Filename.concat temporary_directory "SHA256SUM" in
        let staged_contents = In_channel.read_all staged_file in
        let staged_expected = In_channel.read_all staged_hash |> String.strip in
        if not (String.equal staged_expected (Sha256.digest_string staged_contents))
        then failwith "staged snapshot hash verification failed";
        ignore
          (Yojson.Safe.from_string staged_contents |> Domain.of_yojson |> Or_error.ok_exn
           : Domain.t);
        ignore temporary_config;
        ignore temporary_id;
        fsync_directory temporary_directory;
        Core_unix.rename ~src:temporary_directory ~dst:final_directory;
        replace_pointer config.directory "latest" id;
        replace_pointer config.directory "last-good" id;
        fsync_directory config.directory;
        let committed = load_sync config id |> Or_error.ok_exn in
        summary_of_snapshot config ~latest:true ~last_good:true committed)
      ~finally:(fun () -> remove_temp temporary_directory))
;;

let list config =
  In_thread.run (fun () -> Or_error.try_with_join (fun () -> list_sync config))
;;

let load config id = In_thread.run (fun () -> load_sync config id)

let resolve config selector =
  In_thread.run (fun () ->
    match selector with
    | "latest" | "last-good" ->
      pointer_id config.directory selector
      |> Or_error.bind ~f:(function
        | Some id -> Ok id
        | None -> Or_error.error_s [%message "snapshot pointer is unavailable" selector])
    | value -> Snapshot.Id.of_string value)
;;

let save config ~socket_name snapshot =
  In_thread.run (fun () ->
    Or_error.try_with (fun () -> save_sync config ~socket_name snapshot))
;;

let prune_candidates config ~now catalog =
  let cutoff =
    Time_ns.sub now (Time_ns.Span.of_day (Float.of_int config.retention_days))
  in
  let valid = List.filter catalog.Snapshot.snapshots ~f:Snapshot.is_valid in
  valid
  |> fun snapshots ->
  List.drop snapshots config.minimum_snapshots
  |> List.filter ~f:(fun (item : Snapshot.summary) ->
    Time_ns.(item.created_at < cutoff) && (not item.latest) && not item.last_good)
;;

let delete_bundle config (summary : Snapshot.summary) =
  let directory = Filename.concat config.directory (Snapshot.Id.to_string summary.id) in
  List.iter [ "snapshot.json"; "SHA256SUM" ] ~f:(fun name ->
    let path = Filename.concat directory name in
    match Sys_unix.file_exists path with
    | `Yes -> Core_unix.unlink path
    | `No | `Unknown -> ());
  Core_unix.rmdir directory
;;

let prune config ~now ~apply =
  In_thread.run (fun () ->
    Or_error.try_with_join (fun () ->
      with_lock config ~socket_name:None (fun () ->
        let open Or_error.Let_syntax in
        let%map catalog = list_sync config in
        let candidates = prune_candidates config ~now catalog in
        if apply
        then (
          List.iter candidates ~f:(delete_bundle config);
          if not (List.is_empty candidates) then fsync_directory config.directory);
        candidates)))
;;
