open! Core

module Source = struct
  module T = struct
    type t =
      | Live
      | Snapshot of string
    [@@deriving compare, equal, sexp_of]
  end

  include T

  let label = function
    | Live -> "live"
    | Snapshot id -> "snapshot:" ^ id
  ;;
end

module Server = struct
  type t =
    { available : bool
    ; socket : string option
    ; version : string option
    }
  [@@deriving equal, sexp_of]
end

module Session = struct
  type t =
    { id : string
    ; name : string
    ; attached : bool
    }
  [@@deriving equal, sexp_of]
end

module Window = struct
  type t =
    { id : string
    ; name : string
    ; layout : string
    }
  [@@deriving equal, sexp_of]
end

module Window_link = struct
  type t =
    { id : string
    ; session_id : string
    ; window_id : string
    ; index : int
    ; active : bool
    }
  [@@deriving equal, sexp_of]
end

module Pane = struct
  type t =
    { id : string
    ; window_id : string
    ; index : int
    ; active : bool
    ; title : string
    ; cwd : string
    ; current_command : string
    ; pid : int option
    ; tty : string option
    }
  [@@deriving equal, sexp_of]
end

type t =
  { source : Source.t
  ; server : Server.t
  ; sessions : Session.t String.Map.t
  ; windows : Window.t String.Map.t
  ; window_links : Window_link.t list
  ; panes : Pane.t String.Map.t
  }
[@@deriving equal, sexp_of]

let empty_live ?socket ?version () =
  { source = Live
  ; server = { available = false; socket; version }
  ; sessions = String.Map.empty
  ; windows = String.Map.empty
  ; window_links = []
  ; panes = String.Map.empty
  }
;;

let map_of_unique_list ~kind ~id values =
  List.fold values ~init:(Ok String.Map.empty) ~f:(fun result value ->
    let%bind.Result map = result in
    let key = id value in
    if Map.mem map key
    then Error [%string "duplicate %{kind} id: %{key}"]
    else Ok (Map.set map ~key ~data:value))
;;

let validate t =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  (match
     t.window_links
     |> List.map ~f:(fun link -> link.Window_link.id)
     |> List.find_a_dup ~compare:String.compare
   with
   | Some id -> add [%string "duplicate window link id: %{id}"]
   | None -> ());
  List.iter t.window_links ~f:(fun link ->
    if not (Map.mem t.sessions link.session_id)
    then
      add [%string "window link %{link.id} references missing session %{link.session_id}"];
    if not (Map.mem t.windows link.window_id)
    then
      add [%string "window link %{link.id} references missing window %{link.window_id}"]);
  Map.iter t.panes ~f:(fun pane ->
    if not (Map.mem t.windows pane.window_id)
    then add [%string "pane %{pane.id} references missing window %{pane.window_id}"]);
  t.sessions
  |> Map.iteri ~f:(fun ~key:session_id ~data:_ ->
    let links =
      List.filter t.window_links ~f:(fun link -> String.equal link.session_id session_id)
    in
    let duplicate_indexes =
      links
      |> List.map ~f:(fun link -> link.index)
      |> List.find_a_dup ~compare:Int.compare
    in
    Option.iter duplicate_indexes ~f:(fun index ->
      add [%string "session %{session_id} has duplicate window index %{index#Int}"]);
    let active_count = List.count links ~f:(fun link -> link.active) in
    if (not (List.is_empty links)) && active_count <> 1
    then add [%string "session %{session_id} must have exactly one active window"]);
  t.windows
  |> Map.iteri ~f:(fun ~key:window_id ~data:_ ->
    let panes =
      Map.data t.panes
      |> List.filter ~f:(fun pane -> String.equal pane.window_id window_id)
    in
    let duplicate_indexes =
      panes
      |> List.map ~f:(fun pane -> pane.index)
      |> List.find_a_dup ~compare:Int.compare
    in
    Option.iter duplicate_indexes ~f:(fun index ->
      add [%string "window %{window_id} has duplicate pane index %{index#Int}"]);
    let active_count = List.count panes ~f:(fun pane -> pane.active) in
    if (not (List.is_empty panes)) && active_count <> 1
    then add [%string "window %{window_id} must have exactly one active pane"]);
  match List.rev !errors with
  | [] -> Ok ()
  | errors -> Error errors
;;

let create ~source ~server sessions windows window_links panes =
  match
    ( map_of_unique_list ~kind:"session" ~id:(fun session -> session.Session.id) sessions
    , map_of_unique_list ~kind:"window" ~id:(fun window -> window.Window.id) windows
    , map_of_unique_list ~kind:"pane" ~id:(fun pane -> pane.Pane.id) panes )
  with
  | Ok sessions, Ok windows, Ok panes ->
    let t = { source; server; sessions; windows; window_links; panes } in
    (match validate t with
     | Ok () -> Ok t
     | Error errors -> Error errors)
  | sessions, windows, panes ->
    let errors =
      [ (match sessions with
         | Error error -> Some error
         | Ok _ -> None)
      ; (match windows with
         | Error error -> Some error
         | Ok _ -> None)
      ; (match panes with
         | Error error -> Some error
         | Ok _ -> None)
      ]
      |> List.filter_opt
    in
    Error errors
;;

let ordered_sessions t =
  Map.data t.sessions |> List.sort ~compare:(fun a b -> String.compare a.name b.name)
;;

let links_for_session t ~session_id =
  List.filter t.window_links ~f:(fun link -> String.equal link.session_id session_id)
  |> List.sort ~compare:(fun a b -> Int.compare a.index b.index)
;;

let panes_for_window t ~window_id =
  Map.data t.panes
  |> List.filter ~f:(fun pane -> String.equal pane.window_id window_id)
  |> List.sort ~compare:(fun a b -> Int.compare a.index b.index)
;;

let linked_session_count t ~window_id =
  List.count t.window_links ~f:(fun link -> String.equal link.window_id window_id)
;;

let json_string_option = function
  | None -> `Null
  | Some value -> `String value
;;

let to_yojson t =
  let pane_json (pane : Pane.t) =
    `Assoc
      [ "id", `String pane.id
      ; "index", `Int pane.index
      ; "active", `Bool pane.active
      ; "title", `String pane.title
      ; "cwd", `String pane.cwd
      ; "current_command", `String pane.current_command
      ; "pid", Option.value_map pane.pid ~default:`Null ~f:(fun pid -> `Int pid)
      ; "tty", json_string_option pane.tty
      ]
  in
  let window_json (link : Window_link.t) =
    let window = Map.find_exn t.windows link.window_id in
    `Assoc
      [ "link_id", `String link.id
      ; "id", `String window.id
      ; "index", `Int link.index
      ; "name", `String window.name
      ; "active", `Bool link.active
      ; "shared", `Bool (linked_session_count t ~window_id:window.id > 1)
      ; ( "panes"
        , panes_for_window t ~window_id:window.id
          |> List.map ~f:pane_json
          |> fun panes -> `List panes )
      ]
  in
  let sessions =
    ordered_sessions t
    |> List.map ~f:(fun session ->
      `Assoc
        [ "id", `String session.id
        ; "name", `String session.name
        ; "attached", `Bool session.attached
        ; ( "windows"
          , links_for_session t ~session_id:session.id
            |> List.map ~f:window_json
            |> fun windows -> `List windows )
        ])
  in
  `Assoc
    [ "source", `String (Source.label t.source)
    ; ( "server"
      , `Assoc
          [ "available", `Bool t.server.available
          ; "socket", json_string_option t.server.socket
          ; "version", json_string_option t.server.version
          ] )
    ; "sessions", `List sessions
    ]
;;
