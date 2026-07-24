open! Core
open Async
module Native_snapshot_domain = Tmux_recovery_domain.Native_snapshot
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot

type platform =
  | Auto
  | Macos
  | Linux
  | Other of string

type restore_outcome =
  | Restored of string
  | Skipped_existing

type t =
  { platform : platform
  ; launchd : Launchd.config
  ; systemd : Systemd.config
  ; data_directory : string
  ; state_directory : string
  ; now : unit -> Time_ns.t
  }

let create
  ?(platform = Auto)
  ?launch_agents_directory
  ?systemd_unit_directory
  ?data_directory
  ?state_directory
  ?(now = Time_ns.now)
  ()
  =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let data_home =
    Sys.getenv "XDG_DATA_HOME"
    |> Option.value ~default:(Filename.concat home ".local/share")
  and state_home =
    Sys.getenv "XDG_STATE_HOME"
    |> Option.value ~default:(Filename.concat home ".local/state")
  in
  let launchd = Launchd.default_config ()
  and systemd = Systemd.default_config () in
  { platform
  ; launchd =
      { launchd with
        launch_agents_directory =
          Option.value launch_agents_directory ~default:launchd.launch_agents_directory
      }
  ; systemd =
      { systemd with
        unit_directory =
          Option.value systemd_unit_directory ~default:systemd.unit_directory
      }
  ; data_directory =
      Option.value data_directory ~default:(Filename.concat data_home "tmux-recovery")
  ; state_directory =
      Option.value state_directory ~default:(Filename.concat state_home "tmux-recovery")
  ; now
  }
;;

let detected_platform () =
  let name = Core_unix.uname () |> Core_unix.Utsname.sysname |> String.lowercase in
  match name with
  | "darwin" -> Macos
  | "linux" -> Linux
  | name -> Other name
;;

let unsupported name =
  { Service.manager = Unsupported name
  ; ownership = Absent
  ; periodic_save = Service.empty_component
  ; login_restore = Service.empty_component
  ; binary_path = None
  ; binary_version = None
  ; last_result = None
  ; next_run = None
  ; last_restore = None
  ; conflicts = []
  ; warnings = [ "background service inspection is unavailable on this platform" ]
  }
;;

let restore_run_path t = Filename.concat t.state_directory "restore-run.json"

let read_restore_run t =
  In_thread.run (fun () ->
    Option.try_with (fun () ->
      let open Yojson.Safe.Util in
      let json = In_channel.read_all (restore_run_path t) |> Yojson.Safe.from_string in
      let at = json |> member "at" |> to_string
      and outcome = json |> member "outcome" |> to_string in
      match outcome with
      | "restored" ->
        let snapshot = json |> member "snapshot" |> to_string in
        [%string "%{at} · restored %{snapshot}"]
      | "skipped-existing" -> [%string "%{at} · skipped; tmux already contained sessions"]
      | _ -> failwith "unknown restore-run outcome"))
;;

let native_snapshot_config t =
  let defaults = Native_snapshot.default_config () in
  { defaults with directory = Filename.concat t.data_directory "snapshots" }
;;

let last_timer_run t =
  let config = native_snapshot_config t in
  let%bind catalog = Native_snapshot.list config in
  match catalog with
  | Error _ -> return None
  | Ok catalog ->
    let rec find = function
      | [] -> return None
      | summary :: remaining ->
        if summary.Snapshot.legacy || not (Snapshot.is_valid summary)
        then find remaining
        else (
          let%bind snapshot = Native_snapshot.load config summary.id in
          match snapshot with
          | Ok snapshot
            when Native_snapshot_domain.Trigger.equal
                   snapshot.Native_snapshot_domain.trigger
                   Native_snapshot_domain.Trigger.Timer ->
            return (Some snapshot.created_at)
          | Ok _ | Error _ -> find remaining)
    in
    find catalog.snapshots
;;

let status t =
  let%bind result =
    match
      match t.platform with
      | Auto -> detected_platform ()
      | platform -> platform
    with
    | Macos -> Launchd.status t.launchd
    | Linux -> Systemd.status t.systemd
    | Other name -> return (Ok (unsupported name))
    | Auto -> assert false
  in
  match result with
  | Error _ as error -> return error
  | Ok status ->
    let%bind binary_version =
      if Service.equal_ownership status.ownership Managed
      then (
        match status.binary_path with
        | None -> return status.binary_version
        | Some binary ->
          let%map reported = Process.run ~prog:binary ~args:[ "--version" ] () in
          Result.ok reported |> Option.map ~f:String.strip)
      else return status.binary_version
    and last_restore = read_restore_run t
    and timer_run =
      if Service.equal_ownership status.ownership Managed
         && Service.equal_activation status.periodic_save.activation Loaded
         && Option.is_none status.next_run
      then last_timer_run t
      else return None
    in
    let next_run =
      Option.first_some
        status.next_run
        (Option.bind timer_run ~f:(fun last_run ->
           Service.estimate_next_run ~now:(t.now ()) ~last_run ~interval_seconds:600
           |> Option.map ~f:(fun next ->
             Time_ns.to_string_utc next ^ " · estimated from the last timer save")))
    in
    return (Ok { status with binary_version; next_run; last_restore })
;;

let selected_platform t =
  match t.platform with
  | Auto -> detected_platform ()
  | platform -> platform
;;

let stable_binary t = Filename.concat t.data_directory "bin/current/tmux-recovery"

let resolve_executable name =
  if Filename.is_absolute name
  then
    Option.some_if
      (Poly.equal (Sys_unix.file_exists name) `Yes
       && Result.is_ok (Core_unix.access name [ `Exec ]))
      name
  else
    Sys.getenv "PATH"
    |> Option.value ~default:"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    |> String.split ~on:':'
    |> List.find_map ~f:(fun directory ->
      let path = Filename.concat directory name in
      Option.some_if
        (Poly.equal (Sys_unix.file_exists path) `Yes
         && Result.is_ok (Core_unix.access path [ `Exec ]))
        path)
;;

let command program arguments : Service.command = { program; arguments }

let plan t =
  let open Deferred.Or_error.Let_syntax in
  let%bind current = status t in
  let%bind tmux_path =
    resolve_executable (Sys.getenv "TMUX_RECOVERY_TMUX" |> Option.value ~default:"tmux")
    |> (function
          | Some path -> Ok path
          | None -> Or_error.error_string "could not resolve an executable tmux path")
    |> Deferred.return
  in
  let binary_path = stable_binary t in
  match selected_platform t with
  | Macos ->
    let definitions =
      Launchd.managed_definitions
        t.launchd
        ~binary_path
        ~tmux_path
        ~log_directory:t.state_directory
    in
    let domain = [%string "gui/%{Core_unix.getuid ()#Int}"] in
    return
      { Service.manager = Launchd
      ; stable_binary = binary_path
      ; files =
          List.map definitions ~f:(fun item ->
            { Service.path = item.Launchd.path; contents = item.contents })
      ; enable_commands =
          List.map definitions ~f:(fun item ->
            command "launchctl" [ "bootstrap"; domain; item.path ])
      ; disable_commands =
          List.rev_map definitions ~f:(fun item ->
            command "launchctl" [ "bootout"; domain; item.path ])
      ; conflicts = current.conflicts
      }
  | Linux ->
    let definitions = Systemd.managed_definitions t.systemd ~binary_path ~tmux_path in
    return
      { Service.manager = Systemd
      ; stable_binary = binary_path
      ; files =
          List.map definitions ~f:(fun item ->
            { Service.path = item.Systemd.path; contents = item.contents })
      ; enable_commands =
          [ command "systemctl" [ "--user"; "daemon-reload" ]
          ; command
              "systemctl"
              [ "--user"; "enable"; "--now"; "tmux-recovery-save.timer" ]
          ; command
              "systemctl"
              [ "--user"; "enable"; "--now"; "tmux-recovery-restore.service" ]
          ]
      ; disable_commands =
          [ command
              "systemctl"
              [ "--user"; "disable"; "--now"; "tmux-recovery-restore.service" ]
          ; command
              "systemctl"
              [ "--user"; "disable"; "--now"; "tmux-recovery-save.timer" ]
          ; command "systemctl" [ "--user"; "daemon-reload" ]
          ]
      ; conflicts = current.conflicts
      }
  | Other name -> Deferred.Or_error.error_string ("unsupported platform: " ^ name)
  | Auto -> assert false
;;

let runtime_config t : Runtime.config = { directory = t.data_directory }
let sync_plan t ~source ~version = Runtime.plan (runtime_config t) ~source ~version
let sync t plan = Runtime.apply (runtime_config t) plan
let rollback t = Runtime.rollback (runtime_config t)

let write_file_atomic (file : Service.managed_file) =
  let directory = Filename.dirname file.path in
  Core_unix.mkdir_p ~perm:0o700 directory;
  let temporary =
    Filename.concat
      directory
      [%string ".%{Filename.basename file.path}.tmp-%{Core_unix.getpid ()#Pid}"]
  in
  (match Sys_unix.file_exists temporary with
   | `Yes -> Core_unix.unlink temporary
   | `No | `Unknown -> ());
  Exn.protect
    ~f:(fun () ->
      let fd =
        Core_unix.openfile
          temporary
          ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
          ~perm:0o600
      in
      Exn.protect
        ~f:(fun () ->
          let rec write position =
            if position < String.length file.contents
            then (
              let count =
                Core_unix.write_substring
                  fd
                  ~pos:position
                  ~len:(String.length file.contents - position)
                  ~buf:file.contents
              in
              if count = 0 then failwith "short service definition write";
              write (position + count))
          in
          write 0;
          Core_unix.fsync fd)
        ~finally:(fun () -> Core_unix.close fd);
      Core_unix.rename ~src:temporary ~dst:file.path)
    ~finally:(fun () ->
      match Sys_unix.file_exists temporary with
      | `Yes -> Core_unix.unlink temporary
      | `No | `Unknown -> ())
;;

let record_restore_run t outcome =
  let at = Time_ns.to_string_utc (t.now ()) in
  let outcome_fields =
    match outcome with
    | Restored snapshot -> [ "outcome", `String "restored"; "snapshot", `String snapshot ]
    | Skipped_existing -> [ "outcome", `String "skipped-existing" ]
  in
  let contents = `Assoc (("at", `String at) :: outcome_fields) |> Yojson.Safe.to_string in
  In_thread.run (fun () ->
    Or_error.try_with (fun () ->
      Core_unix.mkdir_p ~perm:0o700 t.state_directory;
      write_file_atomic { Service.path = restore_run_path t; contents = contents ^ "\n" }))
;;

let backup_files files =
  List.map files ~f:(fun (file : Service.managed_file) ->
    let previous =
      match Sys_unix.file_exists file.path with
      | `Yes -> Some (In_channel.read_all file.path)
      | `No | `Unknown -> None
    in
    file.path, previous)
;;

let restore_files backups =
  List.iter backups ~f:(fun (path, previous) ->
    match previous with
    | Some contents -> write_file_atomic { Service.path; contents }
    | None ->
      (match Sys_unix.file_exists path with
       | `Yes -> Core_unix.unlink path
       | `No | `Unknown -> ()))
;;

let run_command (command : Service.command) =
  match resolve_executable command.program with
  | None ->
    return
      (Or_error.error_s [%message "service manager executable not found" command.program])
  | Some program ->
    Process.run ~prog:program ~args:command.arguments () >>| Or_error.map ~f:ignore
;;

let run_commands commands =
  Deferred.Or_error.List.iter commands ~how:`Sequential ~f:run_command
;;

let enable t (plan : Service.plan) =
  if not (List.is_empty plan.conflicts)
  then
    Deferred.Or_error.error_s
      [%message
        "managed services cannot be enabled while legacy conflicts exist"
          (plan.conflicts : string list)]
  else if (not (Poly.equal (Sys_unix.file_exists plan.stable_binary) `Yes))
          || not (Result.is_ok (Core_unix.access plan.stable_binary [ `Exec ]))
  then Deferred.Or_error.error_string "stable runtime is missing or not executable"
  else (
    let%bind backups = In_thread.run (fun () -> backup_files plan.files) in
    let%bind wrote =
      In_thread.run (fun () ->
        Or_error.try_with (fun () ->
          Core_unix.mkdir_p ~perm:0o700 t.state_directory;
          List.iter plan.files ~f:write_file_atomic))
    in
    match wrote with
    | Error error ->
      let%map () = In_thread.run (fun () -> restore_files backups) in
      Error error
    | Ok () ->
      let%bind enabled = run_commands plan.enable_commands in
      (match enabled with
       | Ok () -> return (Ok ())
       | Error error ->
         let%bind () =
           Deferred.List.iter plan.disable_commands ~how:`Sequential ~f:(fun command ->
             run_command command >>| ignore)
         in
         let%map () = In_thread.run (fun () -> restore_files backups) in
         Error error))
;;

let disable _t (plan : Service.plan) = run_commands plan.disable_commands
