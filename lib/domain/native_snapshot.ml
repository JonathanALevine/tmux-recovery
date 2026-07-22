open! Core

module Trigger = struct
  type t =
    | Manual
    | Timer
    | Shutdown
    | Login
    | Import
  [@@deriving compare, equal, sexp_of]

  let to_string = function
    | Manual -> "manual"
    | Timer -> "timer"
    | Shutdown -> "shutdown"
    | Login -> "login"
    | Import -> "import"
  ;;

  let of_string = function
    | "manual" -> Ok Manual
    | "timer" -> Ok Timer
    | "shutdown" -> Ok Shutdown
    | "login" -> Ok Login
    | "import" -> Ok Import
    | value -> Or_error.error_s [%message "invalid snapshot trigger" value]
  ;;
end

type t =
  { id : Snapshot.Id.t
  ; created_at : Time_ns.t
  ; trigger : Trigger.t
  ; tool_version : string
  ; workspace : Workspace.t
  ; codex_resumes : Recovery.Codex_resume.t String.Map.t
  ; codex_unresolved : String.Set.t
  }
[@@deriving equal, sexp_of]

type save_plan =
  { id : Snapshot.Id.t
  ; directory : string
  ; trigger : Trigger.t
  ; session_count : int
  ; window_count : int
  ; pane_count : int
  }
[@@deriving equal, sexp_of]

type restore_plan =
  { snapshot : t
  ; socket_name : string option
  ; recovery : Recovery.plan
  }
[@@deriving equal, sexp_of]

let create
  ?(codex_resumes = String.Map.empty)
  ?(codex_unresolved = String.Set.empty)
  ~id
  ~created_at
  ~trigger
  ~tool_version
  workspace
  =
  match Snapshot.Id.kind id with
  | Resurrect -> Or_error.error_string "native snapshot requires a native snapshot ID"
  | Native ->
    Workspace.validate workspace
    |> Result.map_error ~f:(fun errors ->
      Error.of_string (String.concat errors ~sep:"; "))
    |> Or_error.bind ~f:(fun () ->
      let codex_pane_ids =
        Set.union (Map.keys codex_resumes |> String.Set.of_list) codex_unresolved
      in
      let missing_panes =
        Set.to_list codex_pane_ids
        |> List.filter ~f:(fun pane_id -> not (Map.mem workspace.panes pane_id))
      in
      let overlaps =
        Set.inter (Map.keys codex_resumes |> String.Set.of_list) codex_unresolved
        |> Set.to_list
      in
      if not (List.is_empty missing_panes)
      then
        Or_error.error_s
          [%message
            "Codex recovery records reference unknown panes" (missing_panes : string list)]
      else if not (List.is_empty overlaps)
      then
        Or_error.error_s
          [%message
            "Codex panes cannot be both resumable and unresolved" (overlaps : string list)]
      else
        Ok
          { id
          ; created_at
          ; trigger
          ; tool_version
          ; workspace
          ; codex_resumes
          ; codex_unresolved
          })
;;

let save_plan ~directory (snapshot : t) =
  { id = snapshot.id
  ; directory
  ; trigger = snapshot.trigger
  ; session_count = Map.length snapshot.workspace.sessions
  ; window_count = Map.length snapshot.workspace.windows
  ; pane_count = Map.length snapshot.workspace.panes
  }
;;

let restore_plan ?socket_name (snapshot : t) =
  { snapshot
  ; socket_name
  ; recovery =
      Recovery.plan
        ~codex_resumes:snapshot.codex_resumes
        ~codex_detected:snapshot.codex_unresolved
        snapshot.workspace
  }
;;

let string_option = function
  | None -> `Null
  | Some value -> `String value
;;

let int_option = function
  | None -> `Null
  | Some value -> `Int value
;;

let workspace_to_yojson (workspace : Workspace.t) =
  let sessions =
    Map.data workspace.sessions
    |> List.map ~f:(fun (session : Workspace.Session.t) ->
      `Assoc
        [ "id", `String session.id
        ; "name", `String session.name
        ; "attached", `Bool session.attached
        ])
  and windows =
    Map.data workspace.windows
    |> List.map ~f:(fun (window : Workspace.Window.t) ->
      `Assoc
        [ "id", `String window.id
        ; "name", `String window.name
        ; "layout", `String window.layout
        ])
  and window_links =
    List.map workspace.window_links ~f:(fun (link : Workspace.Window_link.t) ->
      `Assoc
        [ "id", `String link.id
        ; "session_id", `String link.session_id
        ; "window_id", `String link.window_id
        ; "index", `Int link.index
        ; "active", `Bool link.active
        ])
  and panes =
    Map.data workspace.panes
    |> List.map ~f:(fun (pane : Workspace.Pane.t) ->
      `Assoc
        [ "id", `String pane.id
        ; "window_id", `String pane.window_id
        ; "index", `Int pane.index
        ; "active", `Bool pane.active
        ; "title", `String pane.title
        ; "cwd", `String pane.cwd
        ; "current_command", `String pane.current_command
        ; "pid", int_option pane.pid
        ; "tty", string_option pane.tty
        ])
  in
  `Assoc
    [ "tmux_version", string_option workspace.server.version
    ; "sessions", `List sessions
    ; "windows", `List windows
    ; "window_links", `List window_links
    ; "panes", `List panes
    ]
;;

let to_yojson (snapshot : t) =
  let codex_resumes =
    Map.to_alist snapshot.codex_resumes
    |> List.map ~f:(fun (pane_id, resume) ->
      match Recovery.Codex_resume.to_yojson resume with
      | `Assoc fields -> `Assoc (("pane_id", `String pane_id) :: fields)
      | _ -> assert false)
  in
  `Assoc
    [ "schema_version", `Int 2
    ; "id", `String (Snapshot.Id.to_string snapshot.id)
    ; ( "created_at_unix_ns"
      , `String (Time_ns.to_int63_ns_since_epoch snapshot.created_at |> Int63.to_string) )
    ; "trigger", `String (Trigger.to_string snapshot.trigger)
    ; "tool_version", `String snapshot.tool_version
    ; "workspace", workspace_to_yojson snapshot.workspace
    ; ( "applications"
      , `Assoc
          [ "codex", `List codex_resumes
          ; ( "codex_unresolved"
            , `List
                (Set.to_list snapshot.codex_unresolved
                 |> List.map ~f:(fun pane_id -> `String pane_id)) )
          ] )
    ; ( "recovery"
      , Recovery.to_yojson
          (Recovery.plan
             ~codex_resumes:snapshot.codex_resumes
             ~codex_detected:snapshot.codex_unresolved
             snapshot.workspace) )
    ]
;;

let of_yojson json =
  Or_error.try_with (fun () ->
    let open Yojson.Safe.Util in
    let require name json = member name json in
    let schema_version = require "schema_version" json |> to_int in
    if schema_version <> 1 && schema_version <> 2
    then failwithf "unsupported snapshot schema %d" schema_version ();
    let id = require "id" json |> to_string |> Snapshot.Id.of_string |> Or_error.ok_exn in
    let created_at =
      require "created_at_unix_ns" json
      |> to_string
      |> Int63.of_string
      |> Time_ns.of_int63_ns_since_epoch
    in
    let trigger =
      require "trigger" json |> to_string |> Trigger.of_string |> Or_error.ok_exn
    in
    let tool_version = require "tool_version" json |> to_string in
    let workspace_json = require "workspace" json in
    let option_string json =
      match json with
      | `Null -> None
      | value -> Some (to_string value)
    in
    let option_int json =
      match json with
      | `Null -> None
      | value -> Some (to_int value)
    in
    let sessions =
      require "sessions" workspace_json
      |> to_list
      |> List.map ~f:(fun item ->
        { Workspace.Session.id = require "id" item |> to_string
        ; name = require "name" item |> to_string
        ; attached = require "attached" item |> to_bool
        })
    and windows =
      require "windows" workspace_json
      |> to_list
      |> List.map ~f:(fun item ->
        { Workspace.Window.id = require "id" item |> to_string
        ; name = require "name" item |> to_string
        ; layout = require "layout" item |> to_string
        })
    and links =
      require "window_links" workspace_json
      |> to_list
      |> List.map ~f:(fun item ->
        { Workspace.Window_link.id = require "id" item |> to_string
        ; session_id = require "session_id" item |> to_string
        ; window_id = require "window_id" item |> to_string
        ; index = require "index" item |> to_int
        ; active = require "active" item |> to_bool
        })
    and panes =
      require "panes" workspace_json
      |> to_list
      |> List.map ~f:(fun item ->
        { Workspace.Pane.id = require "id" item |> to_string
        ; window_id = require "window_id" item |> to_string
        ; index = require "index" item |> to_int
        ; active = require "active" item |> to_bool
        ; title = require "title" item |> to_string
        ; cwd = require "cwd" item |> to_string
        ; current_command = require "current_command" item |> to_string
        ; pid = require "pid" item |> option_int
        ; tty = require "tty" item |> option_string
        })
    in
    let server : Workspace.Server.t =
      { available = false
      ; socket = None
      ; version = require "tmux_version" workspace_json |> option_string
      }
    in
    let workspace =
      Workspace.create
        ~source:(Snapshot (Snapshot.Id.to_string id))
        ~server
        sessions
        windows
        links
        panes
      |> Result.map_error ~f:(String.concat ~sep:"; ")
      |> Result.ok_or_failwith
    in
    let codex_resumes =
      if schema_version = 1
      then String.Map.empty
      else
        require "applications" json
        |> require "codex"
        |> to_list
        |> List.map ~f:(fun item ->
          let pane_id = require "pane_id" item |> to_string in
          let resume = Recovery.Codex_resume.of_yojson item |> Or_error.ok_exn in
          pane_id, resume)
        |> String.Map.of_alist_or_error
        |> Or_error.ok_exn
    in
    let codex_unresolved =
      if schema_version = 1
      then String.Set.empty
      else (
        let applications = require "applications" json in
        match member "codex_unresolved" applications with
        | `Null -> String.Set.empty
        | value -> value |> to_list |> List.map ~f:to_string |> String.Set.of_list)
    in
    create
      ~codex_resumes
      ~codex_unresolved
      ~id
      ~created_at
      ~trigger
      ~tool_version
      workspace
    |> Or_error.ok_exn)
;;

let save_plan_to_yojson plan =
  `Assoc
    [ "id", `String (Snapshot.Id.to_string plan.id)
    ; "directory", `String plan.directory
    ; "trigger", `String (Trigger.to_string plan.trigger)
    ; "sessions", `Int plan.session_count
    ; "windows", `Int plan.window_count
    ; "panes", `Int plan.pane_count
    ]
;;

let restore_plan_to_yojson plan =
  `Assoc
    [ "snapshot", `String (Snapshot.Id.to_string plan.snapshot.id)
    ; "socket", string_option plan.socket_name
    ; "workspace", Workspace.to_yojson plan.snapshot.workspace
    ; "recovery", Recovery.to_yojson plan.recovery
    ]
;;
