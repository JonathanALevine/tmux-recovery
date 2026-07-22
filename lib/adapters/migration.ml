open! Core
open Async
module Domain = Tmux_recovery_domain.Migration
module Service = Tmux_recovery_domain.Service

type config =
  { home : string
  ; data_directory : string
  }

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let data_home =
    Sys.getenv "XDG_DATA_HOME"
    |> Option.value ~default:(Filename.concat home ".local/share")
  in
  { home; data_directory = Filename.concat data_home "tmux-recovery" }
;;

let digest_file path = In_channel.read_all path |> Sha256.digest_string

let launchd_loaded () =
  let%map result = Process.run_lines ~prog:"launchctl" ~args:[ "list" ] () in
  match result with
  | Error _ -> String.Set.empty
  | Ok lines ->
    List.filter_map lines ~f:(fun line ->
      match String.split line ~on:'\t' with
      | _pid :: _status :: label :: _ -> Some label
      | _ -> None)
    |> String.Set.of_list
;;

let asset ~loaded kind path =
  let exists = Poly.equal (Sys_unix.file_exists path) `Yes in
  { Domain.path; kind; exists; sha256 = Option.some_if exists (digest_file path); loaded }
;;

let plan_sync config ~manager ~managed_services ~now ~nonce ~loaded =
  let backup_directory =
    Filename.concat
      (Filename.concat config.data_directory "migrations")
      [%string "%{Time_ns.to_int63_ns_since_epoch now#Int63}-%{String.prefix nonce 8}"]
  in
  match manager with
  | Service.Launchd ->
    let definitions =
      [ "com.jonathan.tmux-resurrect-save"; "com.jonathan.tmux" ]
      |> List.map ~f:(fun label ->
        ( label
        , Filename.concat
            (Filename.concat config.home "Library/LaunchAgents")
            (label ^ ".plist") ))
    in
    let scripts =
      [ "tmux-resurrect-save-safe"
      ; "tmux-auto-restore"
      ; "tmux-service"
      ; "tmux-terminal-bootstrap.command"
      ]
      |> List.map ~f:(fun name ->
        Filename.concat (Filename.concat config.home "bin") name)
    in
    let assets =
      List.map definitions ~f:(fun (label, path) ->
        asset ~loaded:(Set.mem loaded label) Definition path)
      @ List.map scripts ~f:(asset ~loaded:false Script)
    in
    let domain = [%string "gui/%{Core_unix.getuid ()#Int}"] in
    let disable_commands =
      List.filter_map definitions ~f:(fun (label, path) ->
        Option.some_if
          (Set.mem loaded label)
          { Service.program = "launchctl"; arguments = [ "bootout"; domain; path ] })
    in
    Ok { Domain.manager; backup_directory; assets; disable_commands; managed_services }
  | Systemd ->
    Or_error.error_string "systemd migration inventory is not implemented in this build"
  | Unsupported name -> Or_error.error_string ("unsupported migration manager: " ^ name)
;;

let plan config ~manager ~managed_services ~now ~nonce =
  let%bind loaded =
    match manager with
    | Service.Launchd -> launchd_loaded ()
    | Systemd | Unsupported _ -> return String.Set.empty
  in
  In_thread.run (fun () ->
    Or_error.try_with_join (fun () ->
      plan_sync config ~manager ~managed_services ~now ~nonce ~loaded))
;;

let copy_file ~source ~destination =
  let contents = In_channel.read_all source in
  let fd =
    Core_unix.openfile
      destination
      ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
      ~perm:0o600
  in
  Exn.protect
    ~f:(fun () ->
      let rec write position =
        if position < String.length contents
        then (
          let count =
            Core_unix.write_substring
              fd
              ~pos:position
              ~len:(String.length contents - position)
              ~buf:contents
          in
          if count = 0 then failwith "short migration backup write";
          write (position + count))
      in
      write 0;
      Core_unix.fsync fd)
    ~finally:(fun () -> Core_unix.close fd)
;;

let write_text ~destination contents =
  let fd =
    Core_unix.openfile
      destination
      ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
      ~perm:0o600
  in
  Exn.protect
    ~f:(fun () ->
      let rec write position =
        if position < String.length contents
        then (
          let count =
            Core_unix.write_substring
              fd
              ~pos:position
              ~len:(String.length contents - position)
              ~buf:contents
          in
          if count = 0 then failwith "short migration metadata write";
          write (position + count))
      in
      write 0;
      Core_unix.fsync fd)
    ~finally:(fun () -> Core_unix.close fd)
;;

let replace_active_pointer config backup_directory =
  let migrations = Filename.concat config.data_directory "migrations" in
  let active = Filename.concat migrations "active" in
  let temporary =
    Filename.concat migrations [%string ".active.tmp-%{Core_unix.getpid ()#Pid}"]
  in
  (match Sys_unix.file_exists temporary with
   | `Yes -> Core_unix.unlink temporary
   | `No | `Unknown -> ());
  Core_unix.symlink ~target:(Filename.basename backup_directory) ~link_name:temporary;
  Core_unix.rename ~src:temporary ~dst:active
;;

let create_backup_sync _config (plan : Domain.plan) =
  if Poly.equal (Sys_unix.file_exists plan.backup_directory) `Yes
  then failwith "migration backup directory already exists";
  Core_unix.mkdir_p ~perm:0o700 plan.backup_directory;
  let assets_directory = Filename.concat plan.backup_directory "assets" in
  Core_unix.mkdir ~perm:0o700 assets_directory;
  List.iteri plan.assets ~f:(fun index item ->
    if item.exists
    then (
      let name = [%string "%{index#Int}-%{Filename.basename item.path}"] in
      let destination = Filename.concat assets_directory name in
      copy_file ~source:item.path ~destination;
      let copied_hash = digest_file destination in
      if not (Option.exists item.sha256 ~f:(String.equal copied_hash))
      then failwith "migration backup hash verification failed"));
  let manifest = Domain.to_yojson plan |> Yojson.Safe.pretty_to_string in
  let manifest_path = Filename.concat plan.backup_directory "manifest.json" in
  write_text ~destination:manifest_path manifest;
  let loaded =
    List.filter plan.assets ~f:(fun item -> item.loaded && item.exists)
    |> List.map ~f:(fun item -> item.path)
    |> String.concat ~sep:"\n"
  in
  write_text
    ~destination:(Filename.concat plan.backup_directory "loaded-definitions")
    (loaded ^ if String.is_empty loaded then "" else "\n");
  replace_active_pointer _config plan.backup_directory
;;

let create_backup config plan =
  In_thread.run (fun () -> Or_error.try_with (fun () -> create_backup_sync config plan))
;;

let resolve_program name =
  if Filename.is_absolute name
  then Some name
  else
    Sys.getenv "PATH"
    |> Option.value ~default:"/usr/bin:/bin:/usr/sbin:/sbin"
    |> String.split ~on:':'
    |> List.find_map ~f:(fun directory ->
      let path = Filename.concat directory name in
      Option.some_if (Poly.equal (Sys_unix.file_exists path) `Yes) path)
;;

let run_commands commands =
  Deferred.Or_error.List.iter commands ~how:`Sequential ~f:(fun command ->
    match resolve_program command.Service.program with
    | None -> Deferred.Or_error.error_string "service manager executable is unavailable"
    | Some program ->
      Process.run ~prog:program ~args:command.arguments () >>| Or_error.map ~f:ignore)
;;

let active_legacy_enable_commands config =
  In_thread.run (fun () ->
    Or_error.try_with (fun () ->
      let migrations = Filename.concat config.data_directory "migrations" in
      let active = Filename.concat migrations "active" in
      if not (Poly.equal (Sys_unix.is_symlink active) `Yes)
      then failwith "no active migration rollback bundle";
      let target = Core_unix.readlink active in
      if not (String.equal target (Filename.basename target))
      then failwith "active migration pointer escapes its directory";
      let loaded_file =
        Filename.concat (Filename.concat migrations target) "loaded-definitions"
      in
      let domain = [%string "gui/%{Core_unix.getuid ()#Int}"] in
      In_channel.read_lines loaded_file
      |> List.filter ~f:(Fn.non String.is_empty)
      |> List.map ~f:(fun path ->
        { Service.program = "launchctl"; arguments = [ "bootstrap"; domain; path ] })))
;;
