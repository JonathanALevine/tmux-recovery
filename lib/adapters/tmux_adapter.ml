open! Core
open Async
module Workspace = Tmux_recovery_domain.Workspace

(** Read-only tmux process boundary. *)
type config =
  { executable : string
  ; socket_name : string option
  }

let default_config ?socket_name () =
  let executable = Sys.getenv "TMUX_RECOVERY_TMUX" |> Option.value ~default:"tmux" in
  { executable; socket_name }
;;

let socket_args = function
  | None -> []
  | Some name -> [ "-L"; name ]
;;

(* Keep the record separator printable. tmux can rewrite control characters in format
   arguments when it starts in a minimal (for example, launchd) locale. *)
let separator = "__TMUX_RECOVERY_FIELD_7F3A__"

let format =
  String.concat
    ~sep:separator
    [ "#{session_id}"
    ; "#{session_name}"
    ; "#{session_attached}"
    ; "#{window_id}"
    ; "#{window_index}"
    ; "#{window_name}"
    ; "#{window_active}"
    ; "#{window_layout}"
    ; "#{pane_id}"
    ; "#{pane_index}"
    ; "#{pane_active}"
    ; "#{pane_title}"
    ; "#{pane_current_path}"
    ; "#{pane_current_command}"
    ; "#{pane_pid}"
    ; "#{pane_tty}"
    ]
;;

let int field value =
  match Int.of_string_opt value with
  | Some value -> Ok value
  | None ->
    Or_error.error_s
      [%message "tmux returned an invalid integer" (field : string) (value : string)]
;;

let bool field value =
  let%map.Or_error value = int field value in
  value <> 0
;;

let split_on_substring string ~separator =
  let separator_length = String.length separator in
  let rec loop position fields =
    match String.substr_index string ~pos:position ~pattern:separator with
    | None ->
      let final =
        String.sub string ~pos:position ~len:(String.length string - position)
      in
      List.rev (final :: fields)
    | Some separator_position ->
      let field = String.sub string ~pos:position ~len:(separator_position - position) in
      loop (separator_position + separator_length) (field :: fields)
  in
  loop 0 []
;;

let parse_row row =
  match split_on_substring row ~separator with
  | [ session_id
    ; session_name
    ; session_attached
    ; window_id
    ; window_index
    ; window_name
    ; window_active
    ; window_layout
    ; pane_id
    ; pane_index
    ; pane_active
    ; pane_title
    ; cwd
    ; current_command
    ; pane_pid
    ; pane_tty
    ] ->
    let open Or_error.Let_syntax in
    let%bind attached = bool "session_attached" session_attached
    and window_index = int "window_index" window_index
    and window_active = bool "window_active" window_active
    and pane_index = int "pane_index" pane_index
    and pane_active = bool "pane_active" pane_active in
    let session : Workspace.Session.t =
      { id = session_id; name = session_name; attached }
    in
    let window : Workspace.Window.t =
      { id = window_id; name = window_name; layout = window_layout }
    in
    let link : Workspace.Window_link.t =
      { id = session_id ^ "/" ^ window_id
      ; session_id
      ; window_id
      ; index = window_index
      ; active = window_active
      }
    in
    let pane : Workspace.Pane.t =
      { id = pane_id
      ; window_id
      ; index = pane_index
      ; active = pane_active
      ; title = pane_title
      ; cwd
      ; current_command
      ; pid = Int.of_string_opt pane_pid
      ; tty = Option.some_if (not (String.is_empty pane_tty)) pane_tty
      }
    in
    Ok (session, window, link, pane)
  | fields ->
    Or_error.error_s
      [%message
        "tmux list-panes row did not match the versioned field contract"
          (row : string)
          (List.length fields : int)]
;;

let dedupe_by_id values ~id =
  values
  |> List.fold ~init:String.Map.empty ~f:(fun map value ->
    Map.set map ~key:(id value) ~data:value)
  |> Map.data
;;

let parse_rows ~socket_name ~version rows =
  let open Or_error.Let_syntax in
  let%bind parsed = Or_error.combine_errors (List.map rows ~f:parse_row) in
  let sessions =
    parsed
    |> List.map ~f:(fun (session, _, _, _) -> session)
    |> dedupe_by_id ~id:(fun session -> session.Workspace.Session.id)
  and windows =
    parsed
    |> List.map ~f:(fun (_, window, _, _) -> window)
    |> dedupe_by_id ~id:(fun window -> window.Workspace.Window.id)
  and links =
    parsed
    |> List.map ~f:(fun (_, _, link, _) -> link)
    |> dedupe_by_id ~id:(fun link -> link.Workspace.Window_link.id)
  and panes =
    parsed
    |> List.map ~f:(fun (_, _, _, pane) -> pane)
    |> dedupe_by_id ~id:(fun pane -> pane.Workspace.Pane.id)
  in
  let server : Workspace.Server.t = { available = true; socket = socket_name; version } in
  Workspace.create ~source:Live ~server sessions windows links panes
  |> Result.map_error ~f:(fun errors -> Error.of_string (String.concat errors ~sep:"; "))
;;

let no_server error =
  let message = Error.to_string_hum error |> String.lowercase in
  List.exists
    [ "no server running"; "failed to connect to server"; "no such file or directory" ]
    ~f:(fun substring -> String.is_substring message ~substring)
;;

let observe config =
  let%bind version_result = Process.run ~prog:config.executable ~args:[ "-V" ] () in
  let version = Result.ok version_result |> Option.map ~f:String.strip in
  let args = socket_args config.socket_name @ [ "list-panes"; "-a"; "-F"; format ] in
  let%map result = Process.run_lines ~prog:config.executable ~args () in
  match result with
  | Ok rows -> parse_rows ~socket_name:config.socket_name ~version rows
  | Error error when no_server error ->
    Ok (Workspace.empty_live ?socket:config.socket_name ?version ())
  | Error error -> Error error
;;

let sanitize_capture_line line =
  let length = String.length line in
  let output = Buffer.create length in
  let is_sgr_parameter = function
    | '0' .. '9' | ';' -> true
    | _ -> false
  in
  let rec sgr_end position =
    if position >= length
    then None
    else (
      match line.[position] with
      | 'm' -> Some position
      | character when is_sgr_parameter character -> sgr_end (position + 1)
      | _ -> None)
  in
  let rec copy position =
    if position < length
    then (
      let character = line.[position] in
      let code = Char.to_int character in
      if code = 27 && position + 1 < length && Char.equal line.[position + 1] '['
      then (
        match sgr_end (position + 2) with
        | Some final_position ->
          Buffer.add_substring
            output
            line
            ~pos:position
            ~len:(final_position - position + 1);
          copy (final_position + 1)
        | None ->
          Buffer.add_char output ' ';
          copy (position + 1))
      else (
        Buffer.add_char output (if code < 32 || code = 127 then ' ' else character);
        copy (position + 1)))
  in
  copy 0;
  Buffer.contents output
;;

let trim_trailing_blank_lines lines =
  lines
  |> List.rev
  |> List.drop_while ~f:(fun line -> String.is_empty (String.strip line))
  |> List.rev
;;

let capture_pane config ~pane_id =
  let args =
    socket_args config.socket_name
    @ [ "capture-pane"; "-p"; "-e"; "-t"; pane_id; "-S"; "-40" ]
  in
  let%map result = Process.run_lines ~prog:config.executable ~args () in
  Result.map result ~f:(fun lines ->
    lines |> List.map ~f:sanitize_capture_line |> trim_trailing_blank_lines)
;;

type restore_result =
  { session_ids : string String.Map.t
  ; window_ids : string String.Map.t
  ; pane_ids : string String.Map.t
  }

let run config args =
  Process.run ~prog:config.executable ~args:(socket_args config.socket_name @ args) ()
;;

let run_lines config args =
  Process.run_lines
    ~prog:config.executable
    ~args:(socket_args config.socket_name @ args)
    ()
;;

let run_one_line config args =
  let%map result = run_lines config args in
  Or_error.bind result ~f:(function
    | [ line ] -> Ok line
    | lines ->
      Or_error.error_s
        [%message
          "tmux returned an unexpected number of result lines" (lines : string list)])
;;

let restore_separator = "__TMUX_RECOVERY_RESTORE_91C4__"

let restore_format =
  String.concat ~sep:restore_separator [ "#{session_id}"; "#{window_id}"; "#{pane_id}" ]
;;

let parse_created_triplet line =
  match split_on_substring line ~separator:restore_separator with
  | [ session_id; window_id; pane_id ] -> Ok (session_id, window_id, pane_id)
  | fields ->
    Or_error.error_s
      [%message
        "tmux creation result did not match its contract" line (fields : string list)]
;;

let safe_cwd cwd =
  match Sys_unix.is_directory cwd with
  | `Yes -> cwd
  | `No | `Unknown -> Sys.getenv "HOME" |> Option.value ~default:"/"
;;

let first_pane workspace window_id =
  Workspace.panes_for_window workspace ~window_id |> List.hd
;;

let restore_workspace config workspace =
  let open Deferred.Or_error.Let_syntax in
  let session_ids = ref String.Map.empty in
  let window_ids = ref String.Map.empty in
  let pane_ids = ref String.Map.empty in
  let created_sessions = ref [] in
  let cleanup () =
    Deferred.List.iter !created_sessions ~how:`Sequential ~f:(fun session_id ->
      Deferred.map (run config [ "kill-session"; "-t"; session_id ]) ~f:(fun _ -> ()))
  in
  let configure_window saved_window_id live_window_id live_first_pane_id =
    let panes = Workspace.panes_for_window workspace ~window_id:saved_window_id in
    match panes with
    | [] -> Deferred.Or_error.error_string "cannot restore a window without panes"
    | first :: remaining ->
      pane_ids := Map.set !pane_ids ~key:first.id ~data:live_first_pane_id;
      let%bind () =
        run config [ "select-pane"; "-t"; live_first_pane_id; "-T"; first.title ]
        >>| ignore
      in
      let%bind () =
        Deferred.Or_error.List.iter remaining ~how:`Sequential ~f:(fun pane ->
          let%bind live_pane_id =
            run_one_line
              config
              [ "split-window"
              ; "-d"
              ; "-P"
              ; "-F"
              ; "#{pane_id}"
              ; "-t"
              ; live_window_id
              ; "-c"
              ; safe_cwd pane.cwd
              ]
          in
          pane_ids := Map.set !pane_ids ~key:pane.id ~data:live_pane_id;
          run config [ "select-pane"; "-t"; live_pane_id; "-T"; pane.title ] >>| ignore)
      in
      let saved_window = Map.find_exn workspace.windows saved_window_id in
      let%bind () =
        if String.is_empty (String.strip saved_window.layout)
        then return ()
        else
          run config [ "select-layout"; "-t"; live_window_id; saved_window.layout ]
          >>| ignore
      in
      let active = List.find panes ~f:(fun pane -> pane.active) |> Option.value_exn in
      let live_active = Map.find_exn !pane_ids active.id in
      run config [ "select-pane"; "-t"; live_active ] >>| ignore
  in
  let create_session session first_link =
    let saved_window =
      Map.find_exn workspace.windows first_link.Workspace.Window_link.window_id
    in
    let pane = first_pane workspace saved_window.id |> Option.value_exn in
    let existing_window = Map.find !window_ids saved_window.id in
    let window_name =
      if Option.is_some existing_window then "__tmux_recovery__" else saved_window.name
    in
    let%bind line =
      run_one_line
        config
        [ "new-session"
        ; "-d"
        ; "-P"
        ; "-F"
        ; restore_format
        ; "-s"
        ; session.Workspace.Session.name
        ; "-n"
        ; window_name
        ; "-c"
        ; safe_cwd pane.cwd
        ]
    in
    let%bind live_session_id, live_window_id, live_pane_id =
      parse_created_triplet line |> Deferred.return
    in
    created_sessions := live_session_id :: !created_sessions;
    session_ids := Map.set !session_ids ~key:session.id ~data:live_session_id;
    return (live_session_id, live_window_id, live_pane_id, existing_window)
  in
  let create_window live_session_id link =
    let saved_window =
      Map.find_exn workspace.windows link.Workspace.Window_link.window_id
    in
    let pane = first_pane workspace saved_window.id |> Option.value_exn in
    let target = [%string "%{live_session_id}:%{link.index#Int}"] in
    let%bind line =
      run_one_line
        config
        [ "new-window"
        ; "-d"
        ; "-k"
        ; "-P"
        ; "-F"
        ; restore_format
        ; "-t"
        ; target
        ; "-n"
        ; saved_window.name
        ; "-c"
        ; safe_cwd pane.cwd
        ]
    in
    let%bind _session_id, live_window_id, live_pane_id =
      parse_created_triplet line |> Deferred.return
    in
    return (live_window_id, live_pane_id)
  in
  let link_window live_session_id link live_window_id =
    run
      config
      [ "link-window"
      ; "-d"
      ; "-k"
      ; "-s"
      ; live_window_id
      ; "-t"
      ; [%string "%{live_session_id}:%{link.Workspace.Window_link.index#Int}"]
      ]
    >>| ignore
  in
  let restore () =
    let%bind current = observe config in
    if not (Map.is_empty current.sessions)
    then Deferred.Or_error.error_string "restore target is not empty"
    else (
      let sessions = Workspace.ordered_sessions workspace in
      if List.is_empty sessions
      then Deferred.Or_error.error_string "snapshot contains no sessions"
      else (
        let%bind () =
          Deferred.Or_error.List.iter sessions ~how:`Sequential ~f:(fun session ->
            let links = Workspace.links_for_session workspace ~session_id:session.id in
            match links with
            | [] -> Deferred.Or_error.error_string "snapshot session contains no windows"
            | first_link :: _ ->
              let%bind live_session_id, placeholder_window, placeholder_pane, existing =
                create_session session first_link
              in
              let%bind () =
                match existing with
                | None ->
                  window_ids
                  := Map.set
                       !window_ids
                       ~key:first_link.window_id
                       ~data:placeholder_window;
                  let%bind () =
                    if first_link.index = 0
                    then return ()
                    else
                      run
                        config
                        [ "move-window"
                        ; "-k"
                        ; "-s"
                        ; placeholder_window
                        ; "-t"
                        ; [%string "%{live_session_id}:%{first_link.index#Int}"]
                        ]
                      >>| ignore
                  in
                  configure_window
                    first_link.window_id
                    placeholder_window
                    placeholder_pane
                | Some live_window_id ->
                  link_window live_session_id first_link live_window_id
              in
              let%bind () =
                Deferred.Or_error.List.iter
                  (List.tl_exn links)
                  ~how:`Sequential
                  ~f:(fun link ->
                    match Map.find !window_ids link.window_id with
                    | Some live_window_id ->
                      link_window live_session_id link live_window_id
                    | None ->
                      let%bind live_window_id, live_pane_id =
                        create_window live_session_id link
                      in
                      window_ids
                      := Map.set !window_ids ~key:link.window_id ~data:live_window_id;
                      configure_window link.window_id live_window_id live_pane_id)
              in
              let%bind _ =
                match existing with
                | None -> return ""
                | Some _ ->
                  Deferred.map
                    (run config [ "kill-window"; "-t"; placeholder_window ])
                    ~f:(fun _ -> Ok "")
              in
              let active =
                List.find links ~f:(fun link -> link.active) |> Option.value_exn
              in
              run
                config
                [ "select-window"
                ; "-t"
                ; [%string "%{live_session_id}:%{active.index#Int}"]
                ]
              >>| ignore)
        in
        return
          { session_ids = !session_ids; window_ids = !window_ids; pane_ids = !pane_ids }))
  in
  Deferred.bind (Deferred.Or_error.try_with_join restore) ~f:(function
    | Ok restored -> Deferred.return (Ok restored)
    | Error error -> Deferred.map (cleanup ()) ~f:(fun () -> Error error))
;;

let verify_restored ~saved ~observed (restored : restore_result) =
  let errors = ref [] in
  let error message = errors := message :: !errors in
  if Map.length saved.Workspace.sessions <> Map.length observed.Workspace.sessions
  then error "session count differs";
  if Map.length saved.windows <> Map.length observed.windows
  then error "canonical window count differs";
  if Map.length saved.panes <> Map.length observed.panes then error "pane count differs";
  Map.iteri saved.sessions ~f:(fun ~key:saved_id ~data:saved_session ->
    match Map.find restored.session_ids saved_id with
    | None -> error [%string "missing restored session mapping for %{saved_id}"]
    | Some live_id ->
      (match Map.find observed.sessions live_id with
       | None -> error [%string "restored session %{live_id} is not observable"]
       | Some live_session ->
         if not (String.equal saved_session.name live_session.name)
         then error [%string "session name differs for %{saved_id}"]));
  Map.iteri saved.windows ~f:(fun ~key:saved_id ~data:saved_window ->
    match Map.find restored.window_ids saved_id with
    | None -> error [%string "missing restored window mapping for %{saved_id}"]
    | Some live_id ->
      (match Map.find observed.windows live_id with
       | None -> error [%string "restored window %{live_id} is not observable"]
       | Some live_window ->
         if not (String.equal saved_window.name live_window.name)
         then error [%string "window name differs for %{saved_id}"]));
  Map.iteri saved.panes ~f:(fun ~key:saved_id ~data:(saved_pane : Workspace.Pane.t) ->
    match Map.find restored.pane_ids saved_id with
    | None -> error [%string "missing restored pane mapping for %{saved_id}"]
    | Some live_id ->
      (match Map.find observed.panes live_id with
       | None -> error [%string "restored pane %{live_id} is not observable"]
       | Some (live_pane : Workspace.Pane.t) ->
         let expected_window = Map.find restored.window_ids saved_pane.window_id in
         if not (Option.exists expected_window ~f:(String.equal live_pane.window_id))
         then error [%string "pane window differs for %{saved_id}"];
         if saved_pane.index <> live_pane.index
         then error [%string "pane index differs for %{saved_id}"];
         if not (Bool.equal saved_pane.active live_pane.active)
         then error [%string "active pane differs for %{saved_id}"];
         if not (String.equal (safe_cwd saved_pane.cwd) live_pane.cwd)
         then error [%string "pane working directory differs for %{saved_id}"]));
  List.iter saved.window_links ~f:(fun saved_link ->
    let live_session = Map.find restored.session_ids saved_link.session_id
    and live_window = Map.find restored.window_ids saved_link.window_id in
    match live_session, live_window with
    | Some session_id, Some window_id ->
      let link =
        List.find observed.window_links ~f:(fun live_link ->
          String.equal live_link.session_id session_id
          && String.equal live_link.window_id window_id
          && live_link.index = saved_link.index)
      in
      (match link with
       | None -> error [%string "missing restored window link %{saved_link.id}"]
       | Some live_link ->
         if not (Bool.equal saved_link.active live_link.active)
         then error [%string "active window differs for %{saved_link.id}"])
    | _ -> error [%string "window link mapping is incomplete for %{saved_link.id}"]);
  match List.rev !errors with
  | [] -> Ok ()
  | errors -> Or_error.error_string (String.concat errors ~sep:"; ")
;;

let destroy_restored config (restored : restore_result) =
  Map.data restored.session_ids
  |> String.Set.of_list
  |> Set.to_list
  |> Deferred.List.iter ~how:`Sequential ~f:(fun session_id ->
    Deferred.map (run config [ "kill-session"; "-t"; session_id ]) ~f:(fun _ -> ()))
;;

let safe_command_word value =
  (not (String.is_empty value))
  && String.for_all value ~f:(function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '/' | '.' | '_' | '-' | '+' -> true
    | _ -> false)
;;

let approved_application_names =
  String.Set.of_list
    [ "btop"; "htop"; "top"; "python"; "python3"; "ipython"; "tmux-recovery" ]
;;

let approved_executable executable =
  let executable = executable |> Filename.basename |> String.lowercase in
  if not (Set.mem approved_application_names executable)
  then
    Or_error.error_s
      [%message "executable is not in the native restart allowlist" executable]
  else (
    let home = Sys.getenv "HOME" |> Option.value ~default:"." in
    let path_directories =
      Sys.getenv "PATH"
      |> Option.value ~default:""
      |> String.split ~on:':'
      |> List.filter ~f:(Fn.non String.is_empty)
    in
    let directories =
      [ Filename.concat home ".local/bin"
      ; Filename.concat home "bin"
      ; "/opt/homebrew/bin"
      ; "/usr/local/bin"
      ; "/usr/bin"
      ; "/bin"
      ; "/snap/bin"
      ]
      @ path_directories
      |> String.Set.of_list
      |> Set.to_list
    in
    let executable_names =
      match executable with
      | "python" -> [ "python"; "python3" ]
      | "python3" -> [ "python3"; "python" ]
      | executable -> [ executable ]
    in
    List.find_map directories ~f:(fun directory ->
      List.find_map executable_names ~f:(fun executable_name ->
        let candidate = Filename.concat directory executable_name in
        if safe_command_word candidate
        then (
          match Sys_unix.file_exists candidate with
          | `No | `Unknown -> None
          | `Yes ->
            Option.some_if (Result.is_ok (Core_unix.access candidate [ `Exec ])) candidate)
        else None))
    |> Or_error.of_option
         ~error:
           (Error.create_s [%message "approved application is not installed" executable]))
;;

let restart_approved config ~pane_id ~cwd ~executable =
  match approved_executable executable with
  | Error error -> return (Error error)
  | Ok executable ->
    run config [ "respawn-pane"; "-k"; "-t"; pane_id; "-c"; safe_cwd cwd; executable ]
    >>| Or_error.map ~f:ignore
;;

let resume_codex config ~pane_id ~cwd ~executable ~thread_id ~bypass_approvals =
  let open Deferred.Or_error.Let_syntax in
  let%bind () =
    if Filename.is_absolute executable
       && String.equal (Filename.basename executable) "codex"
       && safe_command_word executable
    then return ()
    else Deferred.Or_error.error_s [%message "unsafe Codex executable path" executable]
  in
  let%bind _ =
    Tmux_recovery_domain.Recovery.Codex_resume.create ~thread_id ~cwd ~bypass_approvals
    |> Deferred.return
  in
  let command =
    [ "respawn-pane"
    ; "-k"
    ; "-t"
    ; pane_id
    ; "-c"
    ; safe_cwd cwd
    ; executable
    ; "resume"
    ; thread_id
    ]
    @ if bypass_approvals then [ "--dangerously-bypass-approvals-and-sandbox" ] else []
  in
  let%bind _ = run config command in
  let%bind _ =
    run config [ "set-window-option"; "-q"; "-t"; pane_id; "automatic-rename"; "off" ]
  in
  let%map _ = run config [ "rename-window"; "-t"; pane_id; "codex" ] in
  ()
;;
