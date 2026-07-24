open! Core
open Async
module Service = Tmux_recovery_domain.Service

type definition =
  { label : string
  ; path : string
  ; contents : string
  }

type inventory =
  { definitions : definition list
  ; loaded : (string * string) list
  ; legacy_scripts : string list
  }

type config =
  { launch_agents_directory : string
  ; bin_directory : string
  }

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  { launch_agents_directory = Filename.concat home "Library/LaunchAgents"
  ; bin_directory = Filename.concat home "bin"
  }
;;

let managed_label label =
  String.is_prefix label ~prefix:"org.tmux-recovery."
  || String.is_prefix label ~prefix:"com.tmux-recovery."
;;

let contains_any value patterns =
  let value = String.lowercase value in
  List.exists patterns ~f:(fun pattern -> String.is_substring value ~substring:pattern)
;;

let save_definition definition =
  contains_any definition.label [ "save"; "resurrect"; "continuum" ]
;;

let restore_definition definition =
  contains_any definition.label [ "restore"; "bootstrap" ]
  || String.equal definition.label "com.jonathan.tmux"
;;

let xml_value contents tag =
  let opening = "<" ^ tag ^ ">" in
  let closing = "</" ^ tag ^ ">" in
  String.substr_index contents ~pattern:opening
  |> Option.bind ~f:(fun start ->
    let value_start = start + String.length opening in
    String.substr_index contents ~pos:value_start ~pattern:closing
    |> Option.map ~f:(fun finish ->
      String.sub contents ~pos:value_start ~len:(finish - value_start) |> String.strip))
;;

let program_arguments contents =
  match String.substr_index contents ~pattern:"<key>ProgramArguments</key>" with
  | None -> []
  | Some position ->
    let remainder =
      String.sub contents ~pos:position ~len:(String.length contents - position)
    in
    let array =
      match String.substr_index remainder ~pattern:"</array>" with
      | None -> remainder
      | Some finish -> String.prefix remainder finish
    in
    let rec values remainder collected =
      match String.substr_index remainder ~pattern:"<string>" with
      | None -> List.rev collected
      | Some start ->
        let value_start = start + String.length "<string>" in
        (match String.substr_index remainder ~pos:value_start ~pattern:"</string>" with
         | None -> List.rev collected
         | Some finish ->
           let value =
             String.sub remainder ~pos:value_start ~len:(finish - value_start)
           in
           let next = finish + String.length "</string>" in
           values
             (String.sub remainder ~pos:next ~len:(String.length remainder - next))
             (String.strip value :: collected))
    in
    values array []
;;

let first_program contents = List.hd (program_arguments contents)

let command_line contents =
  match program_arguments contents with
  | [] -> None
  | program :: arguments ->
    Some (String.concat ~sep:" " (Filename.basename program :: arguments))
;;

let schedule contents =
  match String.substr_index contents ~pattern:"<key>StartInterval</key>" with
  | Some position ->
    String.sub contents ~pos:position ~len:(String.length contents - position)
    |> fun remainder ->
    xml_value remainder "integer" |> Option.map ~f:(fun seconds -> seconds ^ " seconds")
  | None when String.is_substring contents ~substring:"<key>RunAtLoad</key>" ->
    Some "at login"
  | None -> None
;;

let component definitions loaded ~kind =
  let matches = List.filter definitions ~f:kind in
  match matches with
  | [] -> Service.empty_component
  | definition :: _ ->
    let is_loaded = List.Assoc.mem loaded definition.label ~equal:String.equal in
    { Service.activation = (if is_loaded then Loaded else Installed)
    ; schedule = schedule definition.contents
    ; definition = Some definition.path
    ; command = command_line definition.contents
    }
;;

let status_from_inventory inventory =
  let managed, legacy =
    List.partition_tf inventory.definitions ~f:(fun definition ->
      managed_label definition.label)
  in
  let legacy =
    List.filter legacy ~f:(fun definition ->
      contains_any definition.label [ "tmux"; "resurrect"; "continuum" ])
  in
  let has_managed_save = List.exists managed ~f:save_definition in
  let has_managed_restore = List.exists managed ~f:restore_definition in
  let has_legacy_assets =
    (not (List.is_empty legacy)) || not (List.is_empty inventory.legacy_scripts)
  and has_active_legacy =
    List.exists legacy ~f:(fun definition ->
      List.Assoc.mem inventory.loaded definition.label ~equal:String.equal)
  in
  let ownership =
    match
      ( List.is_empty managed
      , has_legacy_assets
      , has_managed_save && has_managed_restore
      , has_active_legacy )
    with
    | true, false, _, _ -> Service.Absent
    | true, true, _, _ -> Legacy
    | false, _, true, false -> Managed
    | false, _, _, _ -> Drifted
  in
  let active_definitions = if List.is_empty managed then legacy else managed in
  let periodic_save =
    component active_definitions inventory.loaded ~kind:save_definition
  in
  let login_restore =
    component active_definitions inventory.loaded ~kind:restore_definition
  in
  let primary =
    Option.first_some
      (List.find active_definitions ~f:save_definition)
      (List.find active_definitions ~f:restore_definition)
  in
  let last_result =
    primary
    |> Option.bind ~f:(fun definition ->
      List.Assoc.find inventory.loaded definition.label ~equal:String.equal)
    |> Option.map ~f:(fun status -> "launchctl exit status " ^ status)
  in
  let conflicts =
    if Service.equal_ownership ownership Legacy
    then List.map legacy ~f:(fun definition -> definition.path) @ inventory.legacy_scripts
    else if Service.equal_ownership ownership Drifted
    then
      List.filter legacy ~f:(fun definition ->
        List.Assoc.mem inventory.loaded definition.label ~equal:String.equal)
      |> List.map ~f:(fun definition -> definition.path)
    else []
  in
  { Service.manager = Launchd
  ; ownership
  ; periodic_save
  ; login_restore
  ; binary_path =
      Option.bind primary ~f:(fun definition -> first_program definition.contents)
  ; binary_version = None
  ; last_result
  ; next_run = None
  ; last_restore = None
  ; conflicts
  ; warnings =
      (match ownership with
       | Legacy -> [ "legacy tmux automation detected; tmux-recovery will not modify it" ]
       | Drifted -> [ "managed and legacy or incomplete service definitions coexist" ]
       | Absent | Managed -> [])
  }
;;

let plist_definition directory name =
  let path = Filename.concat directory name in
  let label =
    if String.is_suffix name ~suffix:".plist"
    then String.drop_suffix name (String.length ".plist")
    else name
  in
  { label; path; contents = In_channel.read_all path }
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

let definitions directory =
  match Sys_unix.is_directory directory with
  | `Yes ->
    Sys_unix.ls_dir directory
    |> List.filter ~f:(String.is_suffix ~suffix:".plist")
    |> List.map ~f:(plist_definition directory)
  | `No -> []
  | `Unknown -> failwith "could not inspect ~/Library/LaunchAgents"
;;

let loaded_services () =
  let%map output = Process.run_lines ~prog:"launchctl" ~args:[ "list" ] () in
  match output with
  | Error _ -> []
  | Ok lines ->
    List.filter_map lines ~f:(fun line ->
      match String.split line ~on:'\t' with
      | _pid :: status :: label :: _ -> Some (label, status)
      | _ -> None)
;;

let status config =
  let%bind loaded = loaded_services () in
  In_thread.run (fun () ->
    Or_error.try_with (fun () ->
      status_from_inventory
        { definitions = definitions config.launch_agents_directory
        ; loaded
        ; legacy_scripts = legacy_scripts config.bin_directory
        }))
;;

let xml_escape value =
  String.concat_map value ~f:(function
    | '&' -> "&amp;"
    | '<' -> "&lt;"
    | '>' -> "&gt;"
    | '"' -> "&quot;"
    | '\'' -> "&apos;"
    | character -> Char.to_string character)
;;

let managed_plist ~label ~arguments ~tmux_path ~schedule ~stdout ~stderr =
  let argument_xml =
    List.map arguments ~f:(fun value ->
      [%string "    <string>%{xml_escape value}</string>"])
    |> String.concat ~sep:"\n"
  in
  let schedule_xml =
    match schedule with
    | `Interval seconds ->
      [%string "  <key>StartInterval</key>\n  <integer>%{seconds#Int}</integer>"]
    | `Login -> "  <key>RunAtLoad</key>\n  <true/>"
  in
  [%string
    {|<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>%{xml_escape label}</string>
  <key>ProgramArguments</key>
  <array>
%{argument_xml}
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TMUX_RECOVERY_TMUX</key>
    <string>%{xml_escape tmux_path}</string>
  </dict>
%{schedule_xml}
  <key>StandardOutPath</key>
  <string>%{xml_escape stdout}</string>
  <key>StandardErrorPath</key>
  <string>%{xml_escape stderr}</string>
</dict>
</plist>
|}]
;;

let managed_definitions config ~binary_path ~tmux_path ~log_directory =
  let definition label arguments schedule log_name =
    { label
    ; path = Filename.concat config.launch_agents_directory (label ^ ".plist")
    ; contents =
        managed_plist
          ~label
          ~arguments
          ~tmux_path
          ~schedule
          ~stdout:(Filename.concat log_directory (log_name ^ ".log"))
          ~stderr:(Filename.concat log_directory (log_name ^ ".error.log"))
    }
  in
  [ definition
      "org.tmux-recovery.save"
      [ binary_path; "snapshot"; "--trigger"; "timer"; "--quiet" ]
      (`Interval 600)
      "save"
  ; definition
      "org.tmux-recovery.restore"
      [ binary_path; "restore"; "--approve"; "--if-empty"; "--quiet" ]
      `Login
      "restore"
  ]
;;
