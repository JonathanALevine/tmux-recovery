open! Core
open Async
module Recovery = Tmux_recovery_domain.Recovery
module Workspace = Tmux_recovery_domain.Workspace

type config =
  { state_database : string
  ; logs_database : string
  ; executable_candidates : string list
  ; process_executable : string
  }

type launch =
  { executable : string
  ; cwd : string
  ; thread_id : string
  ; bypass_approvals : bool
  }

type capture =
  { resumes : Recovery.Codex_resume.t String.Map.t
  ; detected_panes : String.Set.t
  }

let create ~codex_home ~executable_candidates ~process_executable =
  { state_database = Filename.concat codex_home "state_5.sqlite"
  ; logs_database = Filename.concat codex_home "logs_2.sqlite"
  ; executable_candidates
  ; process_executable
  }
;;

let default_config () =
  let home = Sys.getenv "HOME" |> Option.value ~default:"." in
  let codex_home =
    Sys.getenv "CODEX_HOME" |> Option.value ~default:(Filename.concat home ".codex")
  in
  let path_candidates =
    Sys.getenv "PATH"
    |> Option.value ~default:""
    |> String.split ~on:':'
    |> List.filter ~f:(Fn.non String.is_empty)
    |> List.map ~f:(fun directory -> Filename.concat directory "codex")
  in
  let configured_candidate = Sys.getenv "TMUX_RECOVERY_CODEX" |> Option.to_list in
  create
    ~codex_home
    ~process_executable:"ps"
    ~executable_candidates:
      (configured_candidate
       @ [ Filename.concat home ".local/bin/codex"
         ; Filename.concat home "bin/codex"
         ; "/opt/homebrew/bin/codex"
         ; "/usr/local/bin/codex"
         ; "/usr/bin/codex"
         ]
       @ path_candidates)
;;

let with_readonly_database path f =
  match Sys_unix.file_exists path with
  | `No -> Or_error.error_s [%message "Codex database is unavailable" path]
  | `Unknown -> Or_error.error_s [%message "could not inspect Codex database" path]
  | `Yes ->
    Or_error.try_with (fun () ->
      let database = Sqlite3.db_open ~mode:`READONLY path in
      Exn.protect
        ~f:(fun () -> f database)
        ~finally:(fun () -> ignore (Sqlite3.db_close database : bool)))
    |> Or_error.join
;;

let query_one database sql bindings row =
  Or_error.try_with (fun () ->
    let statement = Sqlite3.prepare database sql in
    Exn.protect
      ~f:(fun () ->
        List.iteri bindings ~f:(fun index value ->
          Sqlite3.bind statement (index + 1) value |> Sqlite3.Rc.check);
        match Sqlite3.step statement with
        | ROW -> Some (row statement)
        | DONE -> None
        | code ->
          Sqlite3.Rc.check code;
          None)
      ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t)))
;;

let unrestricted_policy policy =
  Or_error.try_with (fun () ->
    let open Yojson.Safe.Util in
    let kind = Yojson.Safe.from_string policy |> member "type" |> to_string in
    String.equal kind "disabled" || String.equal kind "danger-full-access")
  |> Result.ok
  |> Option.value ~default:false
;;

let resume_of_statement statement =
  let thread_id = Sqlite3.column_text statement 0
  and cwd = Sqlite3.column_text statement 1
  and approval_mode = Sqlite3.column_text statement 2
  and sandbox_policy = Sqlite3.column_text statement 3 in
  Recovery.Codex_resume.create
    ~thread_id
    ~cwd
    ~bypass_approvals:
      (String.equal approval_mode "never" && unrestricted_policy sandbox_policy)
  |> Or_error.ok_exn
;;

let state_by_thread database thread_id =
  query_one
    database
    "SELECT id, cwd, approval_mode, sandbox_policy FROM threads WHERE id = ? AND \
     archived = 0 LIMIT 1"
    [ Sqlite3.Data.TEXT thread_id ]
    resume_of_statement
;;

let latest_state_by_cwd database cwd =
  let current =
    "SELECT id, cwd, approval_mode, sandbox_policy FROM threads WHERE cwd = ? AND \
     archived = 0 ORDER BY updated_at_ms DESC, updated_at DESC, id DESC LIMIT 1"
  and legacy =
    "SELECT id, cwd, approval_mode, sandbox_policy FROM threads WHERE cwd = ? AND \
     archived = 0 ORDER BY updated_at DESC, id DESC LIMIT 1"
  in
  match query_one database current [ Sqlite3.Data.TEXT cwd ] resume_of_statement with
  | Ok _ as result -> result
  | Error _ -> query_one database legacy [ Sqlite3.Data.TEXT cwd ] resume_of_statement
;;

let lookup_latest_for_cwd config ~cwd =
  with_readonly_database config.state_database (fun database ->
    latest_state_by_cwd database cwd)
;;

let thread_for_pid database pid =
  query_one
    database
    "SELECT thread_id FROM logs WHERE process_uuid LIKE ? AND thread_id IS NOT NULL \
     ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT 1"
    [ Sqlite3.Data.TEXT [%string "pid:%{pid#Int}:%"] ]
    (fun statement -> Sqlite3.column_text statement 0)
;;

let thread_for_processes config pids =
  with_readonly_database config.logs_database (fun database ->
    List.find_map pids ~f:(fun pid ->
      match thread_for_pid database pid with
      | Ok (Some thread_id) -> Some thread_id
      | Ok None | Error _ -> None)
    |> Option.some
    |> Or_error.return)
  |> Or_error.map ~f:Option.join
;;

let lookup_for_processes
  ?explicit_thread_id
  ?(allow_cwd_fallback = true)
  config
  ~pids
  ~fallback_cwd
  =
  let state_by_thread_id thread_id =
    with_readonly_database config.state_database (fun database ->
      state_by_thread database thread_id)
  in
  match explicit_thread_id with
  | Some thread_id -> state_by_thread_id thread_id
  | None ->
    let from_process =
      match thread_for_processes config pids with
      | Error _ | Ok None -> Ok None
      | Ok (Some thread_id) -> state_by_thread_id thread_id
    in
    (match from_process with
     | Ok (Some _) as result -> result
     | (Error _ | Ok None) when allow_cwd_fallback ->
       lookup_latest_for_cwd config ~cwd:fallback_cwd
     | Error _ | Ok None -> Ok None)
;;

type process =
  { pid : int
  ; parent : int
  ; command : string
  }

let parse_process line =
  let take_word value =
    let value = String.lstrip value in
    match String.lsplit2 value ~on:' ' with
    | None -> value, ""
    | Some (word, remainder) -> word, remainder
  in
  let pid, remainder = take_word line in
  let parent, command = take_word remainder in
  match Int.of_string_opt pid, Int.of_string_opt parent with
  | Some pid, Some parent -> Some { pid; parent; command = String.strip command }
  | _ -> None
;;

let command_is_codex command =
  let command = String.lowercase command in
  let words = String.split command ~on:' ' |> List.filter ~f:(Fn.non String.is_empty) in
  List.exists words ~f:(fun word ->
    let basename = Filename.basename word in
    String.equal basename "codex"
    || String.equal basename "codex.exe"
    || String.is_substring word ~substring:"/codex/bin/codex"
    || String.is_substring word ~substring:"/@openai/codex/")
;;

let explicit_resume_thread_id command =
  let words = String.split command ~on:' ' |> List.filter ~f:(Fn.non String.is_empty) in
  if not (List.mem words "resume" ~equal:String.equal)
  then None
  else
    List.find words ~f:(fun word ->
      Recovery.Codex_resume.create ~thread_id:word ~cwd:"/" ~bypass_approvals:false
      |> Result.is_ok)
;;

let descendant_pids processes root =
  let children =
    List.fold processes ~init:Int.Map.empty ~f:(fun children process ->
      Map.add_multi children ~key:process.parent ~data:process)
  in
  let rec walk depth pid visited =
    if Set.mem visited pid
    then [], visited
    else (
      let visited = Set.add visited pid in
      Map.find_multi children pid
      |> List.fold ~init:([], visited) ~f:(fun (found, visited) child ->
        let descendants, visited = walk (depth + 1) child.pid visited in
        ((depth + 1, child) :: descendants) @ found, visited))
  in
  walk 0 root Int.Set.empty |> fst
;;

let capture config workspace =
  let%map processes =
    Process.run_lines
      ~prog:config.process_executable
      ~args:[ "-axo"; "pid=,ppid=,command=" ]
      ()
  in
  let processes =
    Result.ok processes |> Option.value ~default:[] |> List.filter_map ~f:parse_process
  in
  let detected_panes =
    Map.data workspace.Workspace.panes
    |> List.filter_map ~f:(fun pane ->
      let related_processes =
        Option.value_map pane.pid ~default:[] ~f:(fun pane_pid ->
          let root =
            List.find processes ~f:(fun process -> process.pid = pane_pid)
            |> Option.to_list
            |> List.map ~f:(fun process -> 0, process)
          in
          root @ descendant_pids processes pane_pid)
      in
      let detected =
        String.equal
          (pane.current_command |> Filename.basename |> String.lowercase)
          "codex"
        || List.exists related_processes ~f:(fun (_, process) ->
          command_is_codex process.command)
      in
      if not detected then None else Some (pane, related_processes))
  in
  let panes_per_cwd =
    List.fold detected_panes ~init:String.Map.empty ~f:(fun counts (pane, _) ->
      Map.update counts pane.Workspace.Pane.cwd ~f:(function
        | None -> 1
        | Some count -> count + 1))
  in
  let resumes =
    detected_panes
    |> List.filter_map ~f:(fun (pane, related_processes) ->
      let pids =
        related_processes
        |> List.sort ~compare:(fun (left, _) (right, _) -> Int.descending left right)
        |> List.map ~f:(fun (_, process) -> process.pid)
      in
      let explicit_thread_id =
        List.find_map related_processes ~f:(fun (_, process) ->
          explicit_resume_thread_id process.command)
      in
      let allow_cwd_fallback =
        Map.find panes_per_cwd pane.cwd |> Option.value ~default:0 |> Int.equal 1
      in
      lookup_for_processes
        ?explicit_thread_id
        ~allow_cwd_fallback
        config
        ~pids
        ~fallback_cwd:pane.cwd
      |> Result.ok
      |> Option.join
      |> Option.map ~f:(fun resume -> pane.id, resume))
    |> String.Map.of_alist_reduce ~f:(fun _ right -> right)
  in
  { resumes
  ; detected_panes =
      List.map detected_panes ~f:(fun (pane, _) -> pane.Workspace.Pane.id)
      |> String.Set.of_list
  }
;;

let executable config =
  List.find config.executable_candidates ~f:(fun path ->
    match Sys_unix.file_exists path with
    | `No | `Unknown -> false
    | `Yes -> Result.is_ok (Core_unix.access path [ `Exec ]))
  |> Or_error.of_option ~error:(Error.of_string "Codex is not installed or executable")
;;

let validate config resume =
  In_thread.run (fun () ->
    let open Or_error.Let_syntax in
    let%bind executable = executable config in
    let%bind current =
      with_readonly_database config.state_database (fun database ->
        state_by_thread database resume.Recovery.Codex_resume.thread_id)
    in
    let%bind current =
      Or_error.of_option
        current
        ~error:
          (Error.create_s
             [%message "Codex thread is no longer available" (resume.thread_id : string)])
    in
    let cwd =
      match Sys_unix.is_directory resume.cwd with
      | `Yes -> resume.cwd
      | `No | `Unknown -> current.cwd
    in
    let%map () =
      match Sys_unix.is_directory cwd with
      | `Yes -> Ok ()
      | `No | `Unknown ->
        Or_error.error_s [%message "Codex working directory is unavailable" cwd]
    in
    { executable
    ; cwd
    ; thread_id = resume.thread_id
    ; bypass_approvals = resume.bypass_approvals
    })
;;
