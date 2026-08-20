open! Core

module Mode = struct
  module T = struct
    type t =
      | Off
      | Dry_run
      | Live
    [@@deriving compare, equal, sexp_of]
  end

  include T
  include Comparable.Make_plain (T)

  let label = function
    | Off -> "off"
    | Dry_run -> "dry-run"
    | Live -> "live"
  ;;

  let of_string = function
    | "off" -> Ok Off
    | "dry-run" | "dry_run" | "dryrun" -> Ok Dry_run
    | "live" -> Ok Live
    | other -> Or_error.error_s [%message "invalid autonomy mode" other]
  ;;
end

type config =
  { mode : Mode.t
  ; grace_seconds : int
  ; persistence_seconds : int
  ; snapshot_before_fire : bool
  }
[@@deriving compare, equal, sexp_of]

let default_config =
  { mode = Mode.Dry_run
  ; grace_seconds = 3600
  ; persistence_seconds = 900
  ; snapshot_before_fire = true
  }
;;

type target =
  { window_id : string
  ; session_id : string
  ; server_identity : string
  ; window_name : string
  ; window_layout : string
  ; panes : (string * string) list
  }
[@@deriving compare, equal, sexp_of]

type candidate =
  { target : target
  ; reason : string
  ; signature : string
  }
[@@deriving compare, equal, sexp_of]

type outcome =
  | Scheduled
  | Fired
      of { at : Time_ns.t; snapshot_id : string option; note : string; dry_run : bool }
  | Cancelled of { at : Time_ns.t; reason : string }
  | Aborted of { at : Time_ns.t; reason : string }
  | Failed of { at : Time_ns.t; reason : string }
[@@deriving compare, equal, sexp_of]

type action =
  { id : string
  ; window_id : string
  ; reason : string
  ; target : target
  ; scheduled_at : Time_ns.t
  ; deadline : Time_ns.t
  ; outcome : outcome
  }
[@@deriving compare, equal, sexp_of]

module Audit_event = struct
  module T = struct
    type t =
      | Scheduled
      | Fired
      | Cancelled
      | Aborted
      | Failed
      | Paused
      | Resumed
      | Policy_changed
    [@@deriving compare, equal, sexp_of]
  end

  include T
  include Comparable.Make_plain (T)
end

type audit_entry =
  { at : Time_ns.t
  ; event : Audit_event.t
  ; action_id : string option
  ; window_id : string option
  ; detail : string
  }
[@@deriving compare, equal, sexp_of]

type candidate_state =
  { eligibility_since : Time_ns.t option
  ; last_signature : string option
  ; suppressed : bool
  }
[@@deriving compare, equal, sexp_of]

type state =
  { config : config
  ; paused : bool
  ; paused_at : Time_ns.t option
  ; next_action_id : int
  ; candidates : candidate_state String.Map.t
  ; active : action list
  ; archived : action list
  ; audit : audit_entry list
  }
[@@deriving compare, equal, sexp_of]

let audit_capacity = 200

let empty ~config =
  { config
  ; paused = false
  ; paused_at = None
  ; next_action_id = 1
  ; candidates = String.Map.empty
  ; active = []
  ; archived = []
  ; audit = []
  }
;;

let paused (state : state) = state.paused

let window_panes workspace ~window_id = Workspace.panes_for_window workspace ~window_id

let detect ~(workspace : Workspace.t) ~(recovery : Recovery.plan) ~viewed =
  let action_by_pane =
    List.fold recovery.decisions ~init:String.Map.empty ~f:(fun acc decision ->
      Map.set acc ~key:decision.pane_id ~data:decision)
  in
  let viewed = String.Set.of_list viewed in
  workspace.windows
  |> Map.data
  |> List.filter_map ~f:(fun window ->
    let blocked =
      window_panes workspace ~window_id:window.id
      |> List.find_map ~f:(fun pane ->
        match Map.find action_by_pane pane.Workspace.Pane.id with
        | Some decision when Recovery.Action.equal decision.action Recovery.Action.Blocked
          -> Some decision
        | _ -> None)
    in
    match blocked with
    | None -> None
    | Some decision ->
      (match Set.mem viewed window.id with
       | true -> None
       | false ->
         let links =
           List.filter workspace.window_links ~f:(fun link ->
             String.equal link.Workspace.Window_link.window_id window.id)
         in
         let session_id =
           match links with
           | [] -> ""
           | link :: _ -> link.session_id
         in
         Some (window.id, session_id, decision.reason)))
;;

let action_id_of (n : int) = "act-" ^ Int.to_string n

let add_audit (state : state) (entry : audit_entry) =
  { state with audit = List.take (entry :: state.audit) audit_capacity }
;;

let find_action (state : state) ~id =
  List.find (state.active @ state.archived) ~f:(fun action -> String.equal action.id id)
;;

let latest_action_for_window (state : state) ~window_id =
  List.find (state.active @ state.archived) ~f:(fun action ->
    String.equal action.window_id window_id)
;;

let find_active_for_window (state : state) ~window_id =
  List.find state.active ~f:(fun action -> String.equal action.window_id window_id)
;;

let last_signature (state : state) ~window_id =
  Option.bind (Map.find state.candidates window_id) ~f:(fun entry -> entry.last_signature)
;;

let candidates (state : state) =
  let first = fun (w, _, _) -> w in
  Map.to_alist state.candidates
  |> List.map ~f:(fun (window_id, entry) ->
    window_id, entry.eligibility_since, entry.suppressed)
  |> List.sort ~compare:(fun a b -> String.compare (first a) (first b))
;;

let set_candidate (state : state) ~window_id (entry : candidate_state) =
  { state with candidates = Map.set state.candidates ~key:window_id ~data:entry }
;;

let suppress (state : state) ~window_id =
  match Map.find state.candidates window_id with
  | Some entry -> set_candidate state ~window_id { entry with suppressed = true }
  | None -> state
;;

let archive (state : state) ~action ~outcome =
  { state
    with active = List.filter state.active ~f:(fun a -> not (String.equal a.id action.id))
  ; archived = { action with outcome } :: state.archived
  }
;;

let outcome_at (outcome : outcome) (action : action) =
  match outcome with
  | Fired { at; _ } -> at
  | Cancelled { at; _ } -> at
  | Aborted { at; _ } -> at
  | Failed { at; _ } -> at
  | Scheduled -> action.scheduled_at
;;

let terminal ~state ~action ~outcome ~event ~detail =
  let state = archive state ~action ~outcome in
  let state =
    add_audit
      state
      { at = outcome_at outcome action
      ; event
      ; action_id = Some action.id
      ; window_id = Some action.window_id
      ; detail
      }
  in
  suppress state ~window_id:action.window_id
;;

let cancel ~now ~id ?(reason = "cancelled by user") (state : state) =
  match find_action state ~id with
  | Some action when [%equal: outcome] action.outcome Scheduled ->
    let outcome = Cancelled { at = now; reason } in
    terminal ~state ~action ~outcome ~event:Audit_event.Cancelled ~detail:reason
  | _ -> state
;;

let pause ~now (state : state) =
  if state.paused
  then state
  else (
    let cancelled = List.length state.active in
    let state =
      List.fold
        state.active
        ~init:state
        ~f:(fun state action ->
          terminal
            ~state
            ~action
            ~outcome:(Cancelled { at = now; reason = "paused" })
            ~event:Audit_event.Cancelled
            ~detail:"paused")
    in
    let state =
      { state
        with active = []
      ; candidates = String.Map.empty
      ; paused = true
      ; paused_at = Some now
      }
    in
    add_audit
      state
      { at = now
      ; event = Audit_event.Paused
      ; action_id = None
      ; window_id = None
      ; detail =
          [%string "paused; cancelled %{cancelled#Int} pending action(s)"]
      })
;;

let resume ~now (state : state) =
  if not state.paused
  then state
  else (
    let state = { state with paused = false; paused_at = None } in
    add_audit
      state
      { at = now
      ; event = Audit_event.Resumed
      ; action_id = None
      ; window_id = None
      ; detail = "resumed; a fresh persistence period is required"
      })
;;

let with_config ~now config (state : state) =
  if [%equal: config] config state.config
  then state
  else (
    let state =
      List.fold
        state.active
        ~init:state
        ~f:(fun state action ->
          terminal
            ~state
            ~action
            ~outcome:(Cancelled { at = now; reason = "policy changed" })
            ~event:Audit_event.Cancelled
            ~detail:"policy changed")
    in
    let state = { state with active = [] ; config ; candidates = String.Map.empty } in
    add_audit
      state
      { at = now
      ; event = Audit_event.Policy_changed
      ; action_id = None
      ; window_id = None
      ; detail =
          [%string
            "mode=%{Mode.label state.config.mode} · grace=%{state.config.grace_seconds#Int}s \
             · persistence=%{state.config.persistence_seconds#Int}s"]
      })
;;

let span_reached ~now since (span : Time_ns.Span.t) =
  Time_ns.Span.(Time_ns.diff now since >= span)
;;

let tick ~now ~(candidates : candidate list) (state : state) =
  if Mode.equal state.config.mode Mode.Off || state.paused
  then state
  else (
    let current =
      candidates
      |> List.map ~f:(fun candidate -> candidate.target.window_id)
      |> String.Set.of_list
    in
    (* Windows that left the funnel: drop their bookkeeping and auto-cancel any
       pending action. Dropping the entry also clears suppression, so a later
       re-entry starts a fresh eligibility cycle. *)
    let leaving =
      Map.keys state.candidates
      |> List.filter ~f:(fun window_id -> not (Set.mem current window_id))
    in
    let state =
      List.fold leaving ~init:state ~f:(fun state window_id ->
        let state = { state with candidates = Map.remove state.candidates window_id } in
        match find_active_for_window state ~window_id with
        | None -> state
        | Some action ->
          let reason = "window left the eligibility funnel" in
          terminal
            ~state
            ~action
            ~outcome:(Cancelled { at = now; reason })
            ~event:Audit_event.Cancelled
            ~detail:reason)
    in
    let state =
      List.fold candidates ~init:state ~f:(fun state candidate ->
        let window_id = candidate.target.window_id in
        let prev = Map.find state.candidates window_id in
        let unchanged =
          match prev with
          | Some entry ->
            Option.exists entry.last_signature ~f:(String.equal candidate.signature)
          | None -> false
        in
        let eligibility_since =
          if unchanged
          then (
            match prev with
            | Some entry -> Some (Option.value entry.eligibility_since ~default:now)
            | None -> Some now)
          else None
        in
        let entry =
          { eligibility_since
          ; last_signature = Some candidate.signature
          ; suppressed = (match prev with Some entry -> entry.suppressed | None -> false)
          }
        in
        let state = set_candidate state ~window_id entry in
        (* A pending action whose window is still a candidate but is no longer
           quiescent is auto-cancelled. *)
        let state, just_cancelled =
          match find_active_for_window state ~window_id with
          | Some action when not unchanged ->
            let reason = "activity changed during the grace countdown" in
            (
              terminal
                ~state
                ~action
                ~outcome:(Cancelled { at = now; reason })
                ~event:Audit_event.Cancelled
                ~detail:reason,
              true)
          | _ -> state, false
        in
        if just_cancelled || entry.suppressed
        then state
        else if Option.is_some (find_active_for_window state ~window_id)
        then state
        else
          (match eligibility_since with
           | Some since when span_reached ~now since (Time_ns.Span.of_int_sec state.config.persistence_seconds)
             ->
             let id = action_id_of state.next_action_id in
             let action =
               { id
               ; window_id
               ; reason = candidate.reason
               ; target = candidate.target
               ; scheduled_at = now
               ; deadline = Time_ns.add now (Time_ns.Span.of_int_sec state.config.grace_seconds)
               ; outcome = Scheduled
               }
             in
             let state =
               { state with active = action :: state.active
                           ; next_action_id = state.next_action_id + 1 }
             in
             add_audit
               state
               { at = now
               ; event = Audit_event.Scheduled
               ; action_id = Some id
               ; window_id = Some window_id
               ; detail =
                   [%string
                     "closes in %{state.config.grace_seconds#Int}s after persistence \
                      threshold"]
               }
           | _ -> state))
    in
    state
  )
;;

let active (state : state) = state.active

let due ~now (state : state) =
  List.filter state.active ~f:(fun action ->
    Time_ns.Span.(Time_ns.diff now action.deadline >= zero))
;;

let remaining ~now (action : action) =
  let d = Time_ns.diff action.deadline now in
  if Time_ns.Span.(d >= zero) then d else Time_ns.Span.zero
;;

let apply_fire ~now ~id ?snapshot_id ~dry_run ~note (state : state) =
  match List.find state.active ~f:(fun action -> String.equal action.id id) with
  | None -> state
  | Some action ->
    let outcome = Fired { at = now; snapshot_id; note; dry_run } in
    terminal ~state ~action ~outcome ~event:Audit_event.Fired ~detail:note
;;

let abort_fire ~now ~id ~reason (state : state) =
  match List.find state.active ~f:(fun action -> String.equal action.id id) with
  | None -> state
  | Some action ->
    terminal
      ~state
      ~action
      ~outcome:(Aborted { at = now; reason })
      ~event:Audit_event.Aborted
      ~detail:reason
;;

let fail_fire ~now ~id ~reason (state : state) =
  match List.find state.active ~f:(fun action -> String.equal action.id id) with
  | None -> state
  | Some action ->
    terminal
      ~state
      ~action
      ~outcome:(Failed { at = now; reason })
      ~event:Audit_event.Failed
      ~detail:reason
;;

let target_matches (action : action) (candidate : candidate) =
  let open Or_error.Let_syntax in
  let%bind () =
    if String.equal action.target.server_identity candidate.target.server_identity
    then Ok ()
    else Or_error.error_string "tmux server identity changed since scheduling"
  in
  let%bind () =
    if String.equal action.window_id candidate.target.window_id
    then Ok ()
    else Or_error.error_string "window ID mismatch"
  in
  let%bind () =
    if String.equal action.target.window_name candidate.target.window_name
    then Ok ()
    else Or_error.error_string "window name changed since scheduling"
  in
  let%bind () =
    if String.equal action.target.window_layout candidate.target.window_layout
    then Ok ()
    else Or_error.error_string "window layout changed since scheduling"
  in
  let%bind () =
    let rec panes_equal = function
      | (a, b) :: rest_a, (c, d) :: rest_b ->
        String.equal a c && String.equal b d && panes_equal (rest_a, rest_b)
      | [], [] -> true
      | _ -> false
    in
    if panes_equal (action.target.panes, candidate.target.panes)
    then Ok ()
    else Or_error.error_string "window panes changed since scheduling"
  in
  return ()
;;

let audit (state : state) = state.audit

let audit_event_label = function
  | Audit_event.Scheduled -> "scheduled"
  | Audit_event.Fired -> "fired"
  | Audit_event.Cancelled -> "cancelled"
  | Audit_event.Aborted -> "aborted"
  | Audit_event.Failed -> "failed"
  | Audit_event.Paused -> "paused"
  | Audit_event.Resumed -> "resumed"
  | Audit_event.Policy_changed -> "policy changed"
;;

let audit_lines (state : state) =
  List.map state.audit ~f:(fun entry ->
    let time = Time_ns.to_string_utc entry.at in
    let who =
      match entry.action_id, entry.window_id with
      | Some action_id, Some window_id -> [%string "%{action_id} %{window_id}"]
      | Some action_id, None -> action_id
      | None, Some window_id -> window_id
      | None, None -> ""
    in
    let who = if String.is_empty who then "" else " " ^ who in
    time ^ " " ^ audit_event_label entry.event ^ who ^ " " ^ entry.detail)
;;

(******************************************************************************)
(* Persistence: versioned JSON (de)serialization. The adapter adds the schema  *)
(* version envelope; the engine owns the payload shapes.                      *)
(******************************************************************************)

let time_to_yojson (t : Time_ns.t) = `String (Time_ns.to_string_utc t)

let time_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  Or_error.try_with (fun () -> Time_ns.of_string_with_utc_offset (to_string json))
;;

let field_option (json : Yojson.Safe.t) (of_value : Yojson.Safe.t -> 'a Or_error.t) =
  (match json with
   | `Null -> Ok None
   | value -> Or_error.map (of_value value) ~f:Option.some)
;;

let config_to_yojson (config : config) =
  `Assoc
    [ "mode", `String (Mode.label config.mode)
    ; "grace_seconds", `Int config.grace_seconds
    ; "persistence_seconds", `Int config.persistence_seconds
    ; "snapshot_before_fire", `Bool config.snapshot_before_fire
    ]
;;

let rec config_of_yojson json =
  Or_error.try_with_join (fun () -> parse_config json)

and parse_config (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let%bind mode = Mode.of_string (to_string (member "mode" json)) in
  let%bind grace_seconds =
    (match member "grace_seconds" json |> to_int with
     | n when n >= 0 -> Ok n
     | _ -> Or_error.error_string "grace_seconds must be a non-negative integer")
  in
  let%bind persistence_seconds =
    (match member "persistence_seconds" json |> to_int with
     | n when n >= 0 -> Ok n
     | _ -> Or_error.error_string "persistence_seconds must be a non-negative integer")
  in
  let snapshot_before_fire = to_bool (member "snapshot_before_fire" json) in
  return { mode; grace_seconds; persistence_seconds; snapshot_before_fire }
;;

let outcome_to_yojson = function
  | Scheduled -> `Assoc [ "kind", `String "scheduled" ]
  | Fired { at; snapshot_id; note; dry_run } ->
    `Assoc
      [ "kind", `String "fired"
      ; "at", time_to_yojson at
      ; "snapshot_id", (match snapshot_id with Some s -> `String s | None -> `Null)
      ; "note", `String note
      ; "dry_run", `Bool dry_run
      ]
  | Cancelled { at; reason } ->
    `Assoc [ "kind", `String "cancelled"; "at", time_to_yojson at; "reason", `String reason ]
  | Aborted { at; reason } ->
    `Assoc [ "kind", `String "aborted"; "at", time_to_yojson at; "reason", `String reason ]
  | Failed { at; reason } ->
    `Assoc [ "kind", `String "failed"; "at", time_to_yojson at; "reason", `String reason ]
;;

let outcome_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let kind = to_string (member "kind" json) in
  match kind with
  | "scheduled" -> Ok Scheduled
  | "fired" ->
    let snapshot_id =
      (match member "snapshot_id" json with `Null -> None | value -> Some (to_string value))
    in
    let note = to_string (member "note" json) in
    let dry_run = to_bool (member "dry_run" json) in
    Or_error.map (time_of_yojson (member "at" json)) ~f:(fun at ->
      Fired { at; snapshot_id; note; dry_run })
  | "cancelled" | "aborted" | "failed" ->
    let reason = to_string (member "reason" json) in
    Or_error.map (time_of_yojson (member "at" json)) ~f:(fun at ->
      match kind with
      | "cancelled" -> Cancelled { at; reason }
      | "aborted" -> Aborted { at; reason }
      | _ -> Failed { at; reason })
  | other -> Or_error.error_s [%message "invalid outcome" other]
;;

let target_to_yojson (target : target) =
  `Assoc
    [ "window_id", `String target.window_id
    ; "session_id", `String target.session_id
    ; "server_identity", `String target.server_identity
    ; "window_name", `String target.window_name
    ; "window_layout", `String target.window_layout
    ; "panes",
        `List
          (List.map target.panes ~f:(fun (pane_id, command) ->
             `Assoc [ "pane_id", `String pane_id; "command", `String command ]))
    ]
;;

let target_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let target = member "target" json in
  let window_id = to_string (member "window_id" target)
  and session_id = to_string (member "session_id" target)
  and server_identity = to_string (member "server_identity" target)
  and window_name = to_string (member "window_name" target)
  and window_layout = to_string (member "window_layout" target) in
  let%bind panes =
    to_list (member "panes" target)
    |> List.map ~f:(fun pane ->
      Ok (to_string (member "pane_id" pane), to_string (member "command" pane)))
    |> Or_error.all
  in
  return
    { window_id
    ; session_id
    ; server_identity
    ; window_name
    ; window_layout
    ; panes = List.sort panes ~compare:(fun (a, _) (b, _) -> String.compare a b)
    }
;;

let action_to_yojson (action : action) =
  `Assoc
    [ "id", `String action.id
    ; "window_id", `String action.window_id
    ; "reason", `String action.reason
    ; "target", target_to_yojson action.target
    ; "scheduled_at", time_to_yojson action.scheduled_at
    ; "deadline", time_to_yojson action.deadline
    ; "outcome", outcome_to_yojson action.outcome
    ]
;;

let action_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let id = to_string (member "id" json) in
  let window_id = to_string (member "window_id" json) in
  let reason = to_string (member "reason" json) in
  let%bind target = target_of_yojson json in
  let%bind scheduled_at = time_of_yojson (member "scheduled_at" json) in
  let%bind deadline = time_of_yojson (member "deadline" json) in
  let%bind outcome = outcome_of_yojson (member "outcome" json) in
  return { id; window_id; reason; target; scheduled_at; deadline; outcome }
;;

let candidate_state_to_yojson (entry : candidate_state) =
  `Assoc
    [ "eligibility_since",
        (match entry.eligibility_since with Some t -> time_to_yojson t | None -> `Null)
    ; "last_signature",
        (match entry.last_signature with Some s -> `String s | None -> `Null)
    ; "suppressed", `Bool entry.suppressed
    ]
;;

let candidate_state_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let%bind eligibility_since =
    field_option (member "eligibility_since" json) time_of_yojson
  in
  let%bind last_signature =
    (match member "last_signature" json with
     | `Null -> Ok None
     | value -> Ok (Some (to_string value)))
  in
  let suppressed = to_bool (member "suppressed" json) in
  return { eligibility_since; last_signature; suppressed }
;;

let audit_event_to_yojson (event : Audit_event.t) =
  match event with
  | Audit_event.Scheduled -> `String "scheduled"
  | Audit_event.Fired -> `String "fired"
  | Audit_event.Cancelled -> `String "cancelled"
  | Audit_event.Aborted -> `String "aborted"
  | Audit_event.Failed -> `String "failed"
  | Audit_event.Paused -> `String "paused"
  | Audit_event.Resumed -> `String "resumed"
  | Audit_event.Policy_changed -> `String "policy_changed"
;;

let audit_event_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  match to_string json with
  | "scheduled" -> Ok Audit_event.Scheduled
  | "fired" -> Ok Audit_event.Fired
  | "cancelled" -> Ok Audit_event.Cancelled
  | "aborted" -> Ok Audit_event.Aborted
  | "failed" -> Ok Audit_event.Failed
  | "paused" -> Ok Audit_event.Paused
  | "resumed" -> Ok Audit_event.Resumed
  | "policy_changed" -> Ok Audit_event.Policy_changed
  | other -> Or_error.error_s [%message "invalid audit event" other]
;;

let audit_entry_to_yojson (entry : audit_entry) =
  `Assoc
    [ "at", time_to_yojson entry.at
    ; "event", audit_event_to_yojson entry.event
    ; "action_id", (match entry.action_id with Some id -> `String id | None -> `Null)
    ; "window_id", (match entry.window_id with Some id -> `String id | None -> `Null)
    ; "detail", `String entry.detail
    ]
;;

let audit_entry_of_yojson (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let%bind at = time_of_yojson (member "at" json) in
  let%bind event = audit_event_of_yojson (member "event" json) in
  let%bind action_id =
    (match member "action_id" json with `Null -> Ok None | v -> Ok (Some (to_string v)))
  in
  let%bind window_id =
    (match member "window_id" json with `Null -> Ok None | v -> Ok (Some (to_string v)))
  in
  let detail = to_string (member "detail" json) in
  return { at; event; action_id; window_id; detail }
;;

let state_to_yojson (state : state) =
  `Assoc
    [ "config", config_to_yojson state.config
    ; "paused", `Bool state.paused
    ; "paused_at", (match state.paused_at with Some t -> time_to_yojson t | None -> `Null)
    ; "next_action_id", `Int state.next_action_id
    ; "candidates",
        `Assoc
          (Map.to_alist state.candidates
           |> List.map ~f:(fun (window_id, entry) -> window_id, candidate_state_to_yojson entry))
    ; "active", `List (List.map state.active ~f:action_to_yojson)
    ; "archived", `List (List.map state.archived ~f:action_to_yojson)
    ; "audit", `List (List.map state.audit ~f:audit_entry_to_yojson)
    ]
;;

let rec state_of_yojson json =
  Or_error.try_with_join (fun () -> parse_state json)

and parse_state (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let open Or_error.Let_syntax in
  let%bind config = config_of_yojson (member "config" json) in
  let%bind paused_at = field_option (member "paused_at" json) time_of_yojson in
  let%bind next_action_id =
    (match member "next_action_id" json |> to_int with
     | n when n >= 1 -> Ok n
     | _ -> Or_error.error_string "next_action_id must be positive")
  in
  let%bind candidate_list =
    to_assoc (member "candidates" json)
    |> List.map ~f:(fun (window_id, value) ->
      Or_error.map (candidate_state_of_yojson value) ~f:(fun entry -> window_id, entry))
    |> Or_error.all
  in
  let%bind active =
    to_list (member "active" json) |> List.map ~f:action_of_yojson |> Or_error.all
  in
  let%bind archived =
    to_list (member "archived" json) |> List.map ~f:action_of_yojson |> Or_error.all
  in
  let%bind audit =
    to_list (member "audit" json) |> List.map ~f:audit_entry_of_yojson |> Or_error.all
  in
  let paused = to_bool (member "paused" json) in
  let candidates =
    List.fold candidate_list ~init:String.Map.empty ~f:(fun acc (window_id, entry) ->
      Map.set acc ~key:window_id ~data:entry)
  in
  return
    { config
    ; paused
    ; paused_at
    ; next_action_id
    ; candidates
    ; active
    ; archived
    ; audit
    }
;;
