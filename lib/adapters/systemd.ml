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

let autonomy_definition definition = contains_any definition.name [ "autonomy" ]
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

let command_line contents =
  config_value contents "ExecStart"
  |> Option.map ~f:(fun command ->
    match String.split command ~on:' ' with
    | [] -> command
    | program :: arguments ->
      String.concat ~sep:" " (Filename.basename program :: arguments))
;;

let schedule contents =
  config_value contents "OnCalendar"
  |> Option.first_some (config_value contents "OnUnitActiveSec")
;;

let component definitions inventory ~kind ~prefer =
  let matching = List.filter definitions ~f:kind in
  match Option.first_some (List.find matching ~f:prefer) (List.hd matching) with
  | None -> Service.empty_component
  | Some definition ->
    let activation =
      if List.mem inventory.active definition.name ~equal:String.equal
      then Service.Loaded
      else if List.mem inventory.enabled definition.name ~equal:String.equal
      then Installed
      else Disabled
    in
    let command =
      Option.first_some
        (command_line definition.contents)
        (List.find_map matching ~f:(fun candidate -> command_line candidate.contents))
    in
    { Service.activation
    ; schedule = schedule definition.contents
    ; definition = Some definition.path
    ; command
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
  let has_managed_autonomy =
    List.exists managed_definitions ~f:autonomy_definition
  in
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
      , has_managed_save && has_managed_restore && has_managed_autonomy
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
  ; periodic_save =
      component
        active_definitions
        inventory
        ~kind:save_definition
        ~prefer:(fun definition -> String.is_suffix definition.name ~suffix:".timer")
  ; autonomy =
      component
        active_definitions
        inventory
        ~kind:autonomy_definition
        ~prefer:(fun definition -> String.is_suffix definition.name ~suffix:".timer")
  ; login_restore =
      component
        active_definitions
        inventory
        ~kind:restore_definition
        ~prefer:(fun definition -> String.is_suffix definition.name ~suffix:".service")
  ; binary_path = Option.bind primary ~f:(fun definition -> binary definition.contents)
  ; binary_version = None
  ; last_result = None
  ; next_run = None
  ; last_restore = None
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

let run_systemctl arguments =
  let%map result = Process.run ~prog:"systemctl" ~args:("--user" :: arguments) () in
  Result.ok result |> Option.map ~f:String.strip
;;

let nonempty_property contents key =
  config_value contents key |> Option.filter ~f:(Fn.non String.is_empty)
;;

let service_result contents =
  nonempty_property contents "Result"
  |> Option.map ~f:(fun result ->
    [ Some result
    ; nonempty_property contents "ExecMainStatus" |> Option.map ~f:(sprintf "exit %s")
    ; nonempty_property contents "ExecMainExitTimestamp"
    ]
    |> List.filter_opt
    |> String.concat ~sep:" · ")
;;

let next_run_of_json contents =
  Option.try_with (fun () ->
    let open Yojson.Safe.Util in
    let next_microseconds =
      Yojson.Safe.from_string contents
      |> to_list
      |> List.hd_exn
      |> member "next"
      |> to_int
    in
    if next_microseconds <= 0
    then None
    else (
      let nanoseconds = Int63.of_string (Int.to_string next_microseconds ^ "000") in
      Some (Time_ns.of_int63_ns_since_epoch nanoseconds |> Time_ns.to_string_utc)))
  |> Option.join
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
    let%bind scripts = In_thread.run (fun () -> legacy_scripts config.bin_directory)
    and last_result_output =
      run_systemctl
        [ "show"
        ; "tmux-recovery-save.service"
        ; "--property=Result"
        ; "--property=ExecMainStatus"
        ; "--property=ExecMainExitTimestamp"
        ; "--no-pager"
        ]
    and next_run_output =
      run_systemctl
        [ "list-timers"
        ; "tmux-recovery-save.timer"
        ; "--all"
        ; "--output=json"
        ; "--no-pager"
        ]
    in
    let status =
      status_from_inventory { definitions; active; enabled; legacy_scripts = scripts }
    in
    let last_result = Option.bind last_result_output ~f:service_result
    and next_run = Option.bind next_run_output ~f:next_run_of_json in
    return (Ok { status with last_result; next_run })
;;

let escape_environment_value value =
  String.concat_map value ~f:(function
    | '\\' -> "\\\\"
    | '"' -> "\\\""
    | '%' -> "%%"
    | '\n' -> "\\n"
    | '\r' -> "\\r"
    | '\t' -> "\\t"
    | character -> Char.to_string character)
;;

let managed_definitions config ~binary_path ~tmux_path ~runtime_path =
  let definition name contents =
    { name; path = Filename.concat config.unit_directory name; contents }
  in
  let runtime_path = escape_environment_value runtime_path in
  [ definition
      "tmux-recovery-save.service"
      [%string
        {|[Unit]
Description=Save the tmux-recovery workspace

[Service]
Type=oneshot
Environment=TMUX_RECOVERY_TMUX=%{tmux_path}
Environment="PATH=%{runtime_path}"
ExecStart=%{binary_path} snapshot --trigger timer --quiet
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
      "tmux-recovery-autonomy.service"
      [%string
        {|[Unit]
Description=Reconcile autonomous tmux-recovery cleanup

[Service]
Type=oneshot
Environment=TMUX_RECOVERY_TMUX=%{tmux_path}
Environment="PATH=%{runtime_path}"
ExecStart=%{binary_path} autonomy tick --quiet
|}]
  ; definition
      "tmux-recovery-autonomy.timer"
      {|[Unit]
Description=Reconcile autonomous tmux-recovery cleanup every 45 seconds

[Timer]
OnBootSec=45s
OnUnitActiveSec=45s
RandomizedDelaySec=5s
Persistent=true
Unit=tmux-recovery-autonomy.service

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
Environment="PATH=%{runtime_path}"
ExecStart=%{binary_path} restore --approve --if-empty --quiet
RemainAfterExit=true

[Install]
WantedBy=default.target
|}]
  ]
;;
