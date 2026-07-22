open! Core
open Async
module Service = Tmux_recovery_domain.Service

type definition =
  { name : string
  ; path : string
  ; contents : string
  }

type inventory =
  { definitions : definition list
  ; active : string list
  ; enabled : string list
  ; legacy_scripts : string list
  }

type config =
  { unit_directory : string
  ; bin_directory : string
  }

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  { unit_directory = Filename.concat home ".config/systemd/user"
  ; bin_directory = Filename.concat home "bin"
  }
;;

let managed name = String.is_prefix name ~prefix:"tmux-recovery-"

let contains_any value patterns =
  let value = String.lowercase value in
  List.exists patterns ~f:(fun pattern -> String.is_substring value ~substring:pattern)
;;

let save_definition definition =
  contains_any definition.name [ "save"; "resurrect"; "continuum" ]
;;

let restore_definition definition =
  contains_any definition.name [ "restore"; "bootstrap" ]
;;

let config_value contents key =
  String.split_lines contents
  |> List.find_map ~f:(fun line ->
    let line = String.strip line in
    String.chop_prefix line ~prefix:(key ^ "=") |> Option.map ~f:String.strip)
;;

let binary contents =
  config_value contents "ExecStart"
  |> Option.bind ~f:(fun command ->
    String.split command ~on:' ' |> List.find ~f:(Fn.non String.is_empty))
;;

let schedule contents =
  config_value contents "OnCalendar"
  |> Option.first_some (config_value contents "OnUnitActiveSec")
;;

let component definitions inventory ~kind =
  match List.find definitions ~f:kind with
  | None -> Service.empty_component
  | Some definition ->
    let activation =
      if List.mem inventory.active definition.name ~equal:String.equal
      then Service.Loaded
      else if List.mem inventory.enabled definition.name ~equal:String.equal
      then Installed
      else Disabled
    in
    { Service.activation
    ; schedule = schedule definition.contents
    ; definition = Some definition.path
    }
;;

let status_from_inventory inventory =
  let managed_definitions, legacy =
    List.partition_tf inventory.definitions ~f:(fun definition -> managed definition.name)
  in
  let legacy =
    List.filter legacy ~f:(fun definition ->
      contains_any definition.name [ "tmux"; "resurrect"; "continuum" ])
  in
  let has_managed_save = List.exists managed_definitions ~f:save_definition in
  let has_managed_restore = List.exists managed_definitions ~f:restore_definition in
  let has_legacy_assets =
    (not (List.is_empty legacy)) || not (List.is_empty inventory.legacy_scripts)
  and has_active_legacy =
    List.exists legacy ~f:(fun definition ->
      List.mem inventory.active definition.name ~equal:String.equal
      || List.mem inventory.enabled definition.name ~equal:String.equal)
  in
  let ownership =
    match
      ( List.is_empty managed_definitions
      , has_legacy_assets
      , has_managed_save && has_managed_restore
      , has_active_legacy )
    with
    | true, false, _, _ -> Service.Absent
    | true, true, _, _ -> Legacy
    | false, _, true, false -> Managed
    | false, _, _, _ -> Drifted
  in
  let active_definitions =
    if List.is_empty managed_definitions then legacy else managed_definitions
  in
  let primary =
    Option.first_some
      (List.find active_definitions ~f:(fun definition ->
         save_definition definition && Option.is_some (binary definition.contents)))
      (List.find active_definitions ~f:(fun definition ->
         restore_definition definition && Option.is_some (binary definition.contents)))
  in
  { Service.manager = Systemd
  ; ownership
  ; periodic_save = component active_definitions inventory ~kind:save_definition
  ; login_restore = component active_definitions inventory ~kind:restore_definition
  ; binary_path = Option.bind primary ~f:(fun definition -> binary definition.contents)
  ; binary_version = None
  ; last_result = None
  ; next_run = None
  ; conflicts =
      (if Service.equal_ownership ownership Legacy
       then
         List.map legacy ~f:(fun definition -> definition.path) @ inventory.legacy_scripts
       else if Service.equal_ownership ownership Drifted
       then
         List.filter legacy ~f:(fun definition ->
           List.mem inventory.active definition.name ~equal:String.equal
           || List.mem inventory.enabled definition.name ~equal:String.equal)
         |> List.map ~f:(fun definition -> definition.path)
       else [])
  ; warnings =
      (match ownership with
       | Legacy -> [ "legacy tmux automation detected; tmux-recovery will not modify it" ]
       | Drifted -> [ "managed and legacy or incomplete service definitions coexist" ]
       | Managed when has_legacy_assets ->
         [ "inactive legacy assets are retained only for migration rollback" ]
       | Absent | Managed -> [])
  }
;;

let definitions directory =
  match Sys_unix.is_directory directory with
  | `Yes ->
    Sys_unix.ls_dir directory
    |> List.filter ~f:(fun name ->
      String.is_suffix name ~suffix:".service" || String.is_suffix name ~suffix:".timer")
    |> List.map ~f:(fun name ->
      let path = Filename.concat directory name in
      { name; path; contents = In_channel.read_all path })
  | `No -> []
  | `Unknown -> failwith "could not inspect the systemd user unit directory"
;;

let legacy_scripts directory =
  match Sys_unix.is_directory directory with
  | `Yes ->
    Sys_unix.ls_dir directory
    |> List.filter ~f:(fun name ->
      contains_any name [ "tmux-service"; "tmux-resurrect"; "tmux-auto-restore" ])
    |> List.map ~f:(Filename.concat directory)
  | `No | `Unknown -> []
;;

let probe unit argument =
  let%map result = Process.run ~prog:"systemctl" ~args:[ "--user"; argument; unit ] () in
  Result.ok result |> Option.map ~f:String.strip
;;

let status config =
  let%bind definitions_result =
    In_thread.run (fun () ->
      Or_error.try_with (fun () -> definitions config.unit_directory))
  in
  match definitions_result with
  | Error _ as error -> return error
  | Ok definitions ->
    let relevant =
      List.filter definitions ~f:(fun definition ->
        managed definition.name
        || contains_any definition.name [ "tmux"; "resurrect"; "continuum" ])
    in
    let%bind probes =
      Deferred.List.map relevant ~how:`Parallel ~f:(fun definition ->
        let%map active = probe definition.name "is-active"
        and enabled = probe definition.name "is-enabled" in
        definition.name, active, enabled)
    in
    let active =
      List.filter_map probes ~f:(fun (name, state, _) ->
        Option.some_if (Option.exists state ~f:(String.equal "active")) name)
    and enabled =
      List.filter_map probes ~f:(fun (name, _, state) ->
        Option.some_if (Option.exists state ~f:(String.equal "enabled")) name)
    in
    let%map scripts = In_thread.run (fun () -> legacy_scripts config.bin_directory) in
    Ok (status_from_inventory { definitions; active; enabled; legacy_scripts = scripts })
;;

let managed_definitions config ~binary_path ~tmux_path =
  let definition name contents =
    { name; path = Filename.concat config.unit_directory name; contents }
  in
  [ definition
      "tmux-recovery-save.service"
      [%string
        {|[Unit]
Description=Save the tmux-recovery workspace

[Service]
Type=oneshot
Environment=TMUX_RECOVERY_TMUX=%{tmux_path}
ExecStart=%{binary_path} snapshots save --trigger timer --quiet
|}]
  ; definition
      "tmux-recovery-save.timer"
      {|[Unit]
Description=Save the tmux-recovery workspace every ten minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=10min
RandomizedDelaySec=30s
Persistent=true
Unit=tmux-recovery-save.service

[Install]
WantedBy=timers.target
|}
  ; definition
      "tmux-recovery-restore.service"
      [%string
        {|[Unit]
Description=Restore the last good tmux-recovery workspace

[Service]
Type=oneshot
Environment=TMUX_RECOVERY_TMUX=%{tmux_path}
ExecStart=%{binary_path} snapshots restore last-good --approve --if-empty --quiet
RemainAfterExit=true

[Install]
WantedBy=default.target
|}]
  ]
;;
