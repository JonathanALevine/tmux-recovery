open! Core
open Async
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

type config =
  { directory : string
  ; manifest_directory : string
  }

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let data_home =
    Sys.getenv "XDG_DATA_HOME"
    |> Option.value ~default:(Filename.concat home ".local/share")
  in
  let directory =
    Sys.getenv "TMUX_RECOVERY_RESURRECT_DIR"
    |> Option.value ~default:(Filename.concat data_home "tmux/resurrect")
  in
  let manifest_directory = Filename.concat data_home "tmux-recovery/manifests" in
  { directory; manifest_directory }
;;

let int_field ~kind ~line_number ~name value errors =
  match Int.of_string_opt value with
  | Some value -> Some value
  | None ->
    errors := [%string "%{kind} row %{line_number#Int}: invalid %{name}"] :: !errors;
    None
;;

let nonempty_field ~kind ~line_number ~name value errors =
  if String.is_empty (String.strip value)
  then (
    errors := [%string "%{kind} row %{line_number#Int}: empty %{name}"] :: !errors;
    false)
  else true
;;

let summarize_lines ~id ~created_at ~size_bytes ~latest ~manifest lines =
  let sessions = ref String.Set.empty in
  let windows = ref String.Set.empty in
  let panes = ref String.Set.empty in
  let errors = ref [] in
  let warnings = ref [] in
  List.iteri lines ~f:(fun index line ->
    let line_number = index + 1 in
    if not (String.is_empty (String.strip line))
    then (
      match String.split line ~on:'\t' with
      | "pane"
        :: session_name
        :: window_index
        :: _window_active
        :: _window_flags
        :: pane_index
        :: _pane_title
        :: _cwd
        :: _pane_active
        :: _command
        :: _full_command
        :: _ ->
        let kind = "pane" in
        let session_ok =
          nonempty_field ~kind ~line_number ~name:"session name" session_name errors
        in
        let window_index =
          int_field ~kind ~line_number ~name:"window index" window_index errors
        in
        let pane_index =
          int_field ~kind ~line_number ~name:"pane index" pane_index errors
        in
        if session_ok then sessions := Set.add !sessions session_name;
        Option.iter window_index ~f:(fun window_index ->
          windows := Set.add !windows [%string "%{session_name}:%{window_index#Int}"]);
        (match window_index, pane_index with
         | Some window_index, Some pane_index ->
           let key = [%string "%{session_name}:%{window_index#Int}.%{pane_index#Int}"] in
           if Set.mem !panes key
           then
             errors
             := [%string "pane row %{line_number#Int}: duplicate %{key}"] :: !errors
           else panes := Set.add !panes key
         | None, _ | _, None -> ())
      | "pane" :: _ ->
        errors
        := [%string "pane row %{line_number#Int}: expected at least 11 fields"] :: !errors
      | "window"
        :: session_name
        :: window_index
        :: _window_name
        :: _window_active
        :: _window_flags
        :: _layout
        :: _automatic_rename
        :: _ ->
        let kind = "window" in
        let session_ok =
          nonempty_field ~kind ~line_number ~name:"session name" session_name errors
        in
        let window_index =
          int_field ~kind ~line_number ~name:"window index" window_index errors
        in
        if session_ok then sessions := Set.add !sessions session_name;
        Option.iter window_index ~f:(fun window_index ->
          windows := Set.add !windows [%string "%{session_name}:%{window_index#Int}"])
      | "window" :: _ ->
        errors
        := [%string "window row %{line_number#Int}: expected at least 8 fields"]
           :: !errors
      | ("state" | "grouped_session") :: _ -> ()
      | record_type :: _ ->
        warnings
        := [%string "row %{line_number#Int}: ignored unknown record type %{record_type}"]
           :: !warnings
      | [] -> ()));
  if Set.is_empty !windows then errors := "snapshot contains no window records" :: !errors;
  if Set.is_empty !panes then errors := "snapshot contains no pane records" :: !errors;
  let validity =
    match List.rev !errors with
    | [] -> Snapshot.Valid
    | errors -> Invalid errors
  in
  { Snapshot.id
  ; created_at
  ; size_bytes
  ; latest
  ; last_good = false
  ; validity
  ; warnings = List.rev !warnings
  ; session_count = Set.length !sessions
  ; window_count = Set.length !windows
  ; pane_count = Set.length !panes
  ; manifest
  ; legacy = not manifest
  }
;;

let catalog_of_summaries ~directory ~directory_exists ~current ~warnings summaries =
  let sorted = Snapshot.sort_newest_first summaries in
  let last_good_id =
    List.find sorted ~f:Snapshot.is_valid |> Option.map ~f:(fun item -> item.Snapshot.id)
  in
  let snapshots =
    List.map sorted ~f:(fun item ->
      { item with
        latest = Option.exists current ~f:(Snapshot.Id.equal item.id)
      ; last_good = Option.exists last_good_id ~f:(Snapshot.Id.equal item.id)
      })
  in
  { Snapshot.directory; directory_exists; snapshots; warnings }
;;

let current_id directory =
  let path = Filename.concat directory "last" in
  match Sys_unix.is_symlink path with
  | `No ->
    Ok
      ( None
      , match Sys_unix.file_exists path with
        | `Yes -> [ "last is not a symlink" ]
        | `No | `Unknown -> [] )
  | `Unknown -> Or_error.error_string "could not inspect the tmux-resurrect last link"
  | `Yes ->
    Or_error.try_with (fun () -> Core_unix.readlink path)
    |> Or_error.bind ~f:(fun target ->
      if not (String.equal target (Filename.basename target))
      then Ok (None, [ "last points outside the snapshot directory and was ignored" ])
      else (
        match Snapshot.Id.of_string target with
        | Ok id -> Ok (Some id, [])
        | Error _ -> Ok (None, [ "last does not name a valid snapshot and was ignored" ])))
;;

let manifest_exists config id =
  let name = Snapshot.Id.to_string id ^ ".json" in
  match Sys_unix.file_exists (Filename.concat config.manifest_directory name) with
  | `Yes -> true
  | `No | `Unknown -> false
;;

let read_summary config ~current id =
  let path = Filename.concat config.directory (Snapshot.Id.to_string id) in
  Or_error.try_with (fun () ->
    let stats = Core_unix.stat path in
    if not (Poly.equal stats.st_kind Core_unix.S_REG)
    then failwith "snapshot is not a regular file";
    let created_at = Time_ns.of_span_since_epoch (Time_ns.Span.of_sec stats.st_mtime) in
    summarize_lines
      ~id
      ~created_at
      ~size_bytes:stats.st_size
      ~latest:(Option.exists current ~f:(Snapshot.Id.equal id))
      ~manifest:(manifest_exists config id)
      (In_channel.read_lines path))
;;

let list_sync config =
  match Sys_unix.is_directory config.directory with
  | `No ->
    Ok
      { Snapshot.directory = config.directory
      ; directory_exists = false
      ; snapshots = []
      ; warnings = [ "snapshot directory does not exist" ]
      }
  | `Unknown -> Or_error.error_string "could not inspect the snapshot directory"
  | `Yes ->
    let open Or_error.Let_syntax in
    let%bind current, link_warnings = current_id config.directory in
    let ids =
      Sys_unix.ls_dir config.directory
      |> List.filter_map ~f:(fun name -> Result.ok (Snapshot.Id.of_string name))
    in
    let%map summaries =
      ids |> List.map ~f:(read_summary config ~current) |> Or_error.combine_errors
    in
    let current_warnings =
      match current with
      | Some id when not (List.exists ids ~f:(Snapshot.Id.equal id)) ->
        [ "last points to a missing snapshot" ]
      | None | Some _ -> []
    in
    catalog_of_summaries
      ~directory:config.directory
      ~directory_exists:true
      ~current
      ~warnings:(link_warnings @ current_warnings)
      summaries
;;

let list config =
  In_thread.run (fun () -> Or_error.try_with_join (fun () -> list_sync config))
;;

let show config id =
  let%map catalog = list config in
  let%bind.Or_error catalog in
  match Snapshot.find catalog id with
  | Some summary -> Ok summary
  | None ->
    Or_error.error_s
      [%message "snapshot not found" (Snapshot.Id.to_string id : string) config.directory]
;;

let decode_field value =
  let value = String.chop_prefix value ~prefix:":" |> Option.value ~default:value in
  let output = Buffer.create (String.length value) in
  let rec loop index =
    if index < String.length value
    then
      if Char.equal value.[index] '\\' && index + 1 < String.length value
      then (
        Buffer.add_char output value.[index + 1];
        loop (index + 2))
      else (
        Buffer.add_char output value.[index];
        loop (index + 1))
  in
  loop 0;
  Buffer.contents output
;;

let workspace_of_lines ~id lines =
  let open Or_error.Let_syntax in
  let session_id name = "legacy-session:" ^ name in
  let window_id session index = [%string "legacy-window:%{session}:%{index#Int}"] in
  let windows = ref []
  and links = ref []
  and panes = ref []
  and session_names = ref String.Set.empty
  and errors = ref [] in
  List.iteri lines ~f:(fun line_index line ->
    let line_number = line_index + 1 in
    match String.split line ~on:'\t' with
    | "window" :: session :: index :: name :: active :: _flags :: layout :: _ ->
      (match Int.of_string_opt index, Int.of_string_opt active with
       | Some index, Some active ->
         let id = window_id session index in
         session_names := Set.add !session_names session;
         windows
         := { Tmux_recovery_domain.Workspace.Window.id; name = decode_field name; layout }
            :: !windows;
         links
         := { Tmux_recovery_domain.Workspace.Window_link.id =
                session_id session ^ "/" ^ id
            ; session_id = session_id session
            ; window_id = id
            ; index
            ; active = active <> 0
            }
            :: !links
       | _ ->
         errors
         := [%string "window row %{line_number#Int} has invalid indexes"] :: !errors)
    | "pane"
      :: session
      :: window_index
      :: _window_active
      :: _flags
      :: pane_index
      :: title
      :: cwd
      :: pane_active
      :: command
      :: _full_command
      :: _ ->
      let pane_fields =
        match Int.of_string_opt pane_active with
        | Some pane_active -> Some (title, cwd, pane_active, command)
        | None ->
          (* tmux-resurrect can omit an empty pane title, shifting the remaining fields
             left by one. Only recover the fixed safe fields; the saved full command
             remains ignored. *)
          Int.of_string_opt cwd
          |> Option.map ~f:(fun active -> "", title, active, pane_active)
      in
      (match
         Int.of_string_opt window_index, Int.of_string_opt pane_index, pane_fields
       with
       | Some window_index, Some pane_index, Some (title, cwd, pane_active, command) ->
         session_names := Set.add !session_names session;
         panes
         := { Tmux_recovery_domain.Workspace.Pane.id =
                [%string "legacy-pane:%{session}:%{window_index#Int}:%{pane_index#Int}"]
            ; window_id = window_id session window_index
            ; index = pane_index
            ; active = pane_active <> 0
            ; title = decode_field title
            ; cwd = decode_field cwd
            ; current_command = decode_field command
            ; pid = None
            ; tty = None
            }
            :: !panes
       | _ ->
         errors := [%string "pane row %{line_number#Int} has invalid indexes"] :: !errors)
    | ("state" | "grouped_session") :: _ | [] -> ()
    | _ -> ());
  let%bind () =
    match List.rev !errors with
    | [] -> Ok ()
    | errors -> Or_error.error_string (String.concat errors ~sep:"; ")
  in
  let sessions =
    Set.to_list !session_names
    |> List.map ~f:(fun name ->
      { Tmux_recovery_domain.Workspace.Session.id = session_id name
      ; name
      ; attached = false
      })
  in
  Tmux_recovery_domain.Workspace.create
    ~source:(Snapshot (Snapshot.Id.to_string id))
    ~server:{ available = false; socket = None; version = None }
    sessions
    !windows
    !links
    !panes
  |> Result.map_error ~f:(fun errors -> Error.of_string (String.concat errors ~sep:"; "))
;;

let load_workspace config id =
  match Snapshot.Id.kind id with
  | Native -> return (Or_error.error_string "native ID is not a resurrect import")
  | Resurrect ->
    let path = Filename.concat config.directory (Snapshot.Id.to_string id) in
    In_thread.run (fun () ->
      Or_error.try_with_join (fun () ->
        let stats = Core_unix.stat path in
        if not (Poly.equal stats.st_kind Core_unix.S_REG)
        then Or_error.error_string "legacy snapshot is not a regular file"
        else workspace_of_lines ~id (In_channel.read_lines path)))
;;
