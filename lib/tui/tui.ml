open! Core
open Async
open Bonsai_term
open Bonsai.Let_syntax
module App_recovery = Tmux_recovery_application.Recovery
module App_service = Tmux_recovery_application.Service
module App_snapshot = Tmux_recovery_application.Snapshot
module Ansi_renderer = Bonsai_term_ansi_text_renderer
module Recovery = Tmux_recovery_domain.Recovery
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

module Page_ref = struct
  module T = struct
    type resource =
      | Workspace of Workspace.Source.t
      | Session of Workspace.Source.t * string
      | Window_link of Workspace.Source.t * string
      | Pane of Workspace.Source.t * string
      | Application of Workspace.Source.t * string
    [@@deriving compare, equal, sexp_of]

    type t =
      | Overview
      | Resource of resource
      | Status
    [@@deriving compare, equal, sexp_of]
  end

  include T
  include Comparable.Make_plain (T)
end

type focus =
  | Navigation
  | Page
[@@deriving equal, sexp_of]

type node =
  { page : Page_ref.t
  ; label : string
  ; badge : string option
  ; children : node list
  }

type visible_node =
  { node : node
  ; depth : int
  ; parent : Page_ref.t option
  }

type preview_request = string * int [@@deriving equal]

type pane_preview =
  | No_preview
  | Loading of preview_request
  | Ready of preview_request * string list
  | Failed of preview_request * string

let decisions_by_pane (plan : Recovery.plan) =
  List.fold plan.decisions ~init:String.Map.empty ~f:(fun decisions decision ->
    Map.set decisions ~key:decision.Recovery.pane_id ~data:decision)
;;

let decision_for decisions pane =
  Map.find decisions pane.Workspace.Pane.id
  |> Option.value ~default:(Recovery.classify pane)
;;

let app_node source (pane : Workspace.Pane.t) (decision : Recovery.decision) =
  { page = Resource (Application (source, pane.id))
  ; label = pane.current_command
  ; badge = Some (Recovery.Action.label decision.action)
  ; children = []
  }
;;

let pane_node source decisions (pane : Workspace.Pane.t) =
  let decision = decision_for decisions pane in
  let children =
    match String.strip pane.Workspace.Pane.current_command with
    | ("" | "sh" | "bash" | "zsh" | "fish" | "dash")
      when not (Recovery.Action.equal decision.action Resume) -> []
    | _ -> [ app_node source pane decision ]
  in
  { page = Resource (Pane (source, pane.id))
  ; label = [%string "pane %{pane.index#Int}"]
  ; badge = (if pane.active then Some "active" else None)
  ; children
  }
;;

let window_node (workspace : Workspace.t) decisions (link : Workspace.Window_link.t) =
  let window =
    Map.find_exn workspace.Workspace.windows link.Workspace.Window_link.window_id
  in
  let shared = Workspace.linked_session_count workspace ~window_id:window.id > 1 in
  { page = Resource (Window_link (workspace.source, link.id))
  ; label = [%string "%{link.index#Int}:%{window.name}"]
  ; badge =
      (match link.active, shared with
       | true, true -> Some "active shared"
       | true, false -> Some "active"
       | false, true -> Some "shared"
       | false, false -> None)
  ; children =
      Workspace.panes_for_window workspace ~window_id:window.id
      |> List.map ~f:(pane_node workspace.source decisions)
  }
;;

let session_node (workspace : Workspace.t) decisions (session : Workspace.Session.t) =
  { page = Resource (Session (workspace.source, session.Workspace.Session.id))
  ; label = session.name
  ; badge = (if session.attached then Some "attached" else None)
  ; children =
      Workspace.links_for_session workspace ~session_id:session.id
      |> List.map ~f:(window_node workspace decisions)
  }
;;

let native_snapshots (catalog : Snapshot.catalog) =
  List.filter catalog.snapshots ~f:(fun summary -> not summary.Snapshot.legacy)
;;

let native_last_good catalog =
  native_snapshots catalog
  |> List.find ~f:(fun summary -> summary.last_good && Snapshot.is_valid summary)
;;

let blocked_decisions (recovery : Recovery.plan) =
  List.filter recovery.decisions ~f:(fun decision ->
    Recovery.Action.equal decision.action Recovery.Action.Blocked)
;;

let status_badge workspace recovery snapshots services =
  let snapshots_ready =
    match snapshots with
    | Error _ -> false
    | Ok catalog -> Option.is_some (native_last_good catalog)
  and services_ready =
    match services with
    | Error _ -> false
    | Ok (status : Service.t) ->
      Service.equal_ownership status.ownership Service.Managed
      && List.is_empty status.conflicts
  in
  Some
    (if workspace.Workspace.server.available
        && snapshots_ready
        && services_ready
        && List.is_empty (blocked_decisions recovery)
     then "ready"
     else "attention")
;;

let navigation (workspace : Workspace.t) recovery snapshots services =
  let decisions = decisions_by_pane recovery in
  let live_children =
    Workspace.ordered_sessions workspace |> List.map ~f:(session_node workspace decisions)
  in
  [ { page = Overview; label = "Overview"; badge = None; children = [] }
  ; { page = Resource (Workspace workspace.source)
    ; label = "Sessions"
    ; badge = Some (if workspace.server.available then "online" else "offline")
    ; children = live_children
    }
  ; { page = Status
    ; label = "Status"
    ; badge = status_badge workspace recovery snapshots services
    ; children = []
    }
  ]
;;

let rec branch_pages nodes =
  List.concat_map nodes ~f:(fun node ->
    if List.is_empty node.children then [] else node.page :: branch_pages node.children)
;;

let visible_nodes workspace recovery snapshots services expanded =
  let rec walk ?parent depth nodes =
    List.concat_map nodes ~f:(fun node ->
      let visible = { node; depth; parent } in
      if (not (List.is_empty node.children)) && Set.mem expanded node.page
      then visible :: walk ~parent:node.page (depth + 1) node.children
      else [ visible ])
  in
  walk 0 (navigation workspace recovery snapshots services)
;;

type model =
  { workspace : Workspace.t
  ; recovery : Recovery.plan
  ; snapshots : Snapshot.catalog Or_error.t
  ; services : Service.t Or_error.t
  ; selected : Page_ref.t
  ; expanded : Page_ref.Set.t
  ; focus : focus
  ; message : string option
  ; preview_generation : int
  ; pane_preview : pane_preview
  }

type action =
  | Move of int
  | Expand
  | Collapse_or_parent
  | Activate
  | Toggle_focus
  | Refresh_started
  | Replace_data of
      Workspace.t Or_error.t
      * Recovery.plan Or_error.t
      * Snapshot.catalog Or_error.t
      * Service.t Or_error.t
  | Preview_started of preview_request
  | Preview_finished of preview_request * string list Or_error.t
  | Clear_preview

let pane_for_window_link workspace link_id =
  let open Workspace in
  match
    List.find workspace.window_links ~f:(fun link -> String.equal link.id link_id)
  with
  | None -> None
  | Some link ->
    let panes = Workspace.panes_for_window workspace ~window_id:link.window_id in
    (match List.find panes ~f:(fun pane -> pane.Pane.active) with
     | Some pane -> Some pane
     | None -> List.hd panes)
;;

let pane_id_of_page workspace = function
  | Page_ref.Resource (Pane (_, pane_id)) | Page_ref.Resource (Application (_, pane_id))
    -> Some pane_id
  | Page_ref.Resource (Window_link (_, link_id)) ->
    pane_for_window_link workspace link_id |> Option.map ~f:(fun pane -> pane.id)
  | _ -> None
;;

let with_selected model selected =
  let previous_pane = pane_id_of_page model.workspace model.selected in
  let selected_pane = pane_id_of_page model.workspace selected in
  { model with
    selected
  ; message = None
  ; pane_preview =
      (if [%equal: string option] previous_pane selected_pane
       then model.pane_preview
       else No_preview)
  }
;;

let selected_index visible selected =
  List.findi visible ~f:(fun _ item -> Page_ref.equal item.node.page selected)
  |> Option.value_map ~default:0 ~f:fst
;;

let page_exists workspace recovery snapshots services expanded page =
  visible_nodes workspace recovery snapshots services expanded
  |> List.exists ~f:(fun item -> Page_ref.equal item.node.page page)
;;

let apply_action _context model action =
  let visible =
    visible_nodes
      model.workspace
      model.recovery
      model.snapshots
      model.services
      model.expanded
  in
  let current_index = selected_index visible model.selected in
  let current = List.nth visible current_index in
  match action with
  | Move delta ->
    let next_index =
      Int.clamp_exn
        (current_index + delta)
        ~min:0
        ~max:(Int.max 0 (List.length visible - 1))
    in
    let selected =
      Option.value_map
        (List.nth visible next_index)
        ~default:model.selected
        ~f:(fun item -> item.node.page)
    in
    with_selected model selected
  | Expand ->
    (match current with
     | Some { node = { children = _ :: _; page; _ }; _ } ->
       { model with expanded = Set.add model.expanded page }
     | _ -> { model with focus = Page })
  | Collapse_or_parent ->
    (match current with
     | Some { node = { page; children = _ :: _; _ }; _ } when Set.mem model.expanded page
       -> { model with expanded = Set.remove model.expanded page }
     | Some { parent = Some selected; _ } -> with_selected model selected
     | _ -> model)
  | Activate ->
    (match current with
     | Some { node = { page; children = _ :: _; _ }; _ } ->
       let expanded =
         if Set.mem model.expanded page
         then Set.remove model.expanded page
         else Set.add model.expanded page
       in
       { model with expanded }
     | _ -> { model with focus = Page })
  | Toggle_focus ->
    { model with
      focus =
        (match model.focus with
         | Navigation -> Page
         | Page -> Navigation)
    }
  | Refresh_started -> { model with message = Some "refreshing recovery state…" }
  | Replace_data (workspace_result, recovery_result, snapshots, services) ->
    let workspace =
      match workspace_result with
      | Ok workspace -> workspace
      | Error _ -> model.workspace
    in
    let recovery = Result.ok recovery_result |> Option.value ~default:model.recovery in
    let valid_branches =
      branch_pages (navigation workspace recovery snapshots services)
      |> Page_ref.Set.of_list
    in
    let expanded = Set.inter model.expanded valid_branches in
    let selected =
      if page_exists workspace recovery snapshots services expanded model.selected
      then model.selected
      else Overview
    in
    let unavailable =
      List.count
        [ Result.is_error workspace_result
        ; Result.is_error recovery_result
        ; Result.is_error snapshots
        ; Result.is_error services
        ]
        ~f:Fn.id
    in
    { model with
      workspace
    ; recovery
    ; snapshots
    ; services
    ; expanded
    ; selected
    ; message =
        Some
          (if unavailable = 0
           then "sessions, snapshots, and automation refreshed"
           else [%string "refresh completed · %{unavailable#Int} source(s) unavailable"])
    ; preview_generation = model.preview_generation + 1
    ; pane_preview = No_preview
    }
  | Preview_started request -> { model with pane_preview = Loading request }
  | Preview_finished (request, result) ->
    (match model.pane_preview with
     | Loading current_request when [%equal: preview_request] current_request request ->
       (match result with
        | Ok lines -> { model with pane_preview = Ready (request, lines) }
        | Error error ->
          { model with
            pane_preview = Failed (request, Error.to_string_hum error |> String.strip)
          })
     | No_preview | Loading _ | Ready _ | Failed _ -> model)
  | Clear_preview -> { model with pane_preview = No_preview }
;;

let terminal_foreground = Attr.Color.Expert.default
let terminal_background = Attr.Color.Expert.default
let cyan = Attr.Color.Expert.lightcyan
let green = Attr.Color.Expert.lightgreen
let amber = Attr.Color.Expert.lightyellow
let red = Attr.Color.Expert.lightred
let violet = Attr.Color.Expert.lightmagenta
let text_color = terminal_foreground
let muted = Attr.Color.Expert.lightblack
let selected_text = Attr.Color.Expert.lightwhite
let selected_bg = Attr.Color.Expert.blue

let action_color action =
  match action with
  | Recovery.Action.Shell_fallback -> muted
  | Recovery.Action.Restart | Recovery.Action.Restart_clean -> green
  | Recovery.Action.Resume -> violet
  | Recovery.Action.Blocked -> amber
;;

let program_color command =
  let program = command |> String.strip |> String.lowercase |> Filename.basename in
  match program with
  | "btop" | "htop" | "top" -> cyan
  | "codex" -> violet
  | "python" | "python3" | "ipython" -> amber
  | "vi" | "vim" | "nvim" | "emacs" -> green
  | "ssh" | "mosh" -> Attr.Color.Expert.lightblue
  | "sh" | "bash" | "zsh" | "fish" | "dash" | "" -> muted
  | _ -> text_color
;;

let node_color model (node : node) =
  match node.page with
  | Page_ref.Overview -> cyan
  | Resource (Workspace _) -> if model.workspace.server.available then green else red
  | Resource (Session (_, session_id)) ->
    (match Map.find model.workspace.sessions session_id with
     | Some session when session.attached -> green
     | Some session -> program_color session.name
     | None -> red)
  | Resource (Window_link (_, link_id)) ->
    (match
       List.find model.workspace.window_links ~f:(fun link ->
         String.equal link.id link_id)
     with
     | Some link when link.active -> cyan
     | Some _ -> text_color
     | None -> red)
  | Resource (Pane (_, pane_id)) ->
    (match Map.find model.workspace.panes pane_id with
     | Some pane ->
       let decision = decision_for (decisions_by_pane model.recovery) pane in
       action_color decision.action
     | None -> red)
  | Resource (Application (_, pane_id)) ->
    (match Map.find model.workspace.panes pane_id with
     | Some pane -> program_color pane.current_command
     | None -> red)
  | Status ->
    (match status_badge model.workspace model.recovery model.snapshots model.services with
     | Some "ready" -> green
     | Some _ -> amber
     | None -> cyan)
;;

let crop_to view ~width ~height =
  let r = Int.max 0 (View.width view - width) in
  let b = Int.max 0 (View.height view - height) in
  View.crop ~r ~b view
;;

let panel ~title ~width ~height body =
  let title =
    View.text
      ~attrs:[ Attr.bold; Attr.fg cyan; Attr.bg terminal_background ]
      (" " ^ title ^ String.make (Int.max 0 (width - String.length title - 1)) ' ')
  in
  let content = View.vcat (title :: body) |> crop_to ~width ~height in
  let backdrop =
    View.rectangle ~attrs:[ Attr.bg terminal_background ] ~width ~height ()
  in
  View.zcat [ content; backdrop ]
;;

let render_navigation model ~width ~height =
  let visible =
    visible_nodes
      model.workspace
      model.recovery
      model.snapshots
      model.services
      model.expanded
  in
  let selected_index = selected_index visible model.selected in
  let row_capacity = Int.max 1 (height - 1) in
  let first_visible = Int.max 0 (selected_index - row_capacity + 1) in
  let rows =
    visible
    |> List.mapi ~f:(fun index { node; depth; _ } ->
      let selected = index = selected_index in
      let marker =
        match node.children with
        | [] -> "  "
        | _ when Set.mem model.expanded node.page -> "▾ "
        | _ -> "▸ "
      in
      let prefix = String.make (depth * 2) ' ' ^ marker in
      let badge =
        Option.value_map node.badge ~default:"" ~f:(fun badge -> "  [" ^ badge ^ "]")
      in
      let attrs =
        if selected
        then [ Attr.bold; Attr.fg selected_text; Attr.bg selected_bg ]
        else [ Attr.fg (node_color model node); Attr.bg terminal_background ]
      in
      View.text ~attrs (prefix ^ node.label ^ badge))
    |> fun rows ->
    List.slice
      rows
      first_visible
      (Int.min (List.length rows) (first_visible + row_capacity))
  in
  panel
    ~title:(if equal_focus model.focus Navigation then "NAVIGATION ◀" else "NAVIGATION")
    ~width
    ~height
    rows
;;

let plain ?(color = text_color) text =
  View.text ~attrs:[ Attr.fg color; Attr.bg terminal_background ] text
;;

let heading text =
  View.text ~attrs:[ Attr.bold; Attr.fg cyan; Attr.bg terminal_background ] text
;;

let field name value = View.hcat [ plain ~color:muted (name ^ ": "); plain value ]

let lookup_link workspace id =
  List.find workspace.Workspace.window_links ~f:(fun link -> String.equal link.id id)
;;

let recovery_count (recovery : Recovery.plan) action =
  List.count recovery.decisions ~f:(fun decision ->
    Recovery.Action.equal decision.action action)
;;

let pane_location (workspace : Workspace.t) pane_id =
  match Map.find workspace.panes pane_id with
  | None -> pane_id
  | Some pane ->
    let locations =
      workspace.window_links
      |> List.filter ~f:(fun link -> String.equal link.window_id pane.window_id)
      |> List.filter_map ~f:(fun link ->
        Map.find workspace.sessions link.session_id
        |> Option.map ~f:(fun session ->
          [%string "%{session.name}:%{link.index#Int}.%{pane.index#Int}"]))
      |> List.dedup_and_sort ~compare:String.compare
    in
    (match locations with
     | [] -> pane_id
     | locations -> String.concat locations ~sep:" / ")
;;

let component_status (component : Service.component) =
  let state = Service.activation_label component.activation in
  match component.schedule with
  | None -> state
  | Some schedule -> state ^ " · " ^ schedule
;;

let component_health (component : Service.component) =
  let mark =
    match component.activation with
    | Service.Loaded -> "PASS"
    | Service.Installed | Service.Disabled | Service.Not_installed | Service.Unknown ->
      "WARN"
  in
  mark ^ " · " ^ component_status component
;;

let decision_lines decision =
  [ heading decision.Recovery.observed
  ; field "Action" (Recovery.Action.label decision.action)
  ; field "Fidelity" decision.fidelity
  ; field "Policy" (Option.value decision.rule_id ~default:"none")
  ; plain ""
  ; plain ~color:(action_color decision.action) decision.reason
  ]
;;

let newest_lines_that_fit lines ~line_limit =
  let lines_to_drop = Int.max 0 (List.length lines - line_limit) in
  List.drop lines lines_to_drop
;;

let bytes value =
  if Int64.(value >= 1_048_576L)
  then sprintf "%.1f MiB" (Int64.to_float value /. 1_048_576.)
  else if Int64.(value >= 1024L)
  then sprintf "%.1f KiB" (Int64.to_float value /. 1024.)
  else Int64.to_string value ^ " B"
;;

let warning_lines warnings =
  List.map warnings ~f:(fun warning -> plain ~color:amber ("Warning: " ^ warning))
;;

let pane_preview_lines
  ?(title = "Latest pane output")
  ?(subtitle = "Bottom of pane · read-only · refresh with r")
  model
  pane_id
  ~line_limit
  =
  let contents =
    match model.pane_preview with
    | Loading ((requested_pane, _) as _request) when String.equal requested_pane pane_id
      -> [ plain ~color:muted "Capturing current pane contents…" ]
    | Ready ((requested_pane, _), lines) when String.equal requested_pane pane_id ->
      (match lines with
       | [] -> [ plain ~color:muted "(pane is blank)" ]
       | lines ->
         lines
         |> newest_lines_that_fit ~line_limit
         |> List.map ~f:(fun line -> Ansi_renderer.render (Ansi_text.parse line)))
    | Failed ((requested_pane, _), error) when String.equal requested_pane pane_id ->
      [ plain ~color:amber ("Preview unavailable: " ^ error) ]
    | No_preview | Loading _ | Ready _ | Failed _ ->
      [ plain ~color:muted "Preparing pane preview…" ]
  in
  [ plain ""; heading title; plain ~color:muted subtitle; plain "" ] @ contents
;;

let detail_lines model ~height =
  let preview_line_limit = Int.max 1 (height - 11) in
  let workspace = model.workspace in
  match model.selected with
  | Overview ->
    let snapshot_count =
      match model.snapshots with
      | Ok catalog -> Int.to_string (List.length (native_snapshots catalog))
      | Error _ -> "unavailable"
    in
    [ heading "tmux-recovery"
    ; plain "A conservative recovery control plane for tmux."
    ; plain ""
    ; field "tmux" (if workspace.server.available then "online" else "offline")
    ; field "Sessions" (Int.to_string (Map.length workspace.sessions))
    ; field "Canonical windows" (Int.to_string (Map.length workspace.windows))
    ; field "Panes" (Int.to_string (Map.length workspace.panes))
    ; field "Native snapshots" (snapshot_count ^ " saved · rolling limit 10")
    ; plain ""
    ; plain ~color:muted "Guarded mutations require explicit approval in the CLI."
    ]
  | Resource (Workspace _source) ->
    [ heading "Sessions"
    ; field "Source" (Workspace.Source.label workspace.source)
    ; field "Server" (if workspace.server.available then "running" else "not running")
    ; field "Version" (Option.value workspace.server.version ~default:"unknown")
    ; field "Socket" (Option.value workspace.server.socket ~default:"default")
    ]
  | Resource (Session (_source, id)) ->
    (match Map.find workspace.sessions id with
     | None -> [ heading "Session ended" ]
     | Some session ->
       [ heading session.name
       ; field "Typed ID" session.id
       ; field "Attached" (Bool.to_string session.attached)
       ; field
           "Window links"
           (Int.to_string
              (List.length (Workspace.links_for_session workspace ~session_id:id)))
       ])
  | Resource (Window_link (_source, id)) ->
    (match lookup_link workspace id with
     | None -> [ heading "Window link ended" ]
     | Some link ->
       let window = Map.find_exn workspace.windows link.window_id in
       (match pane_for_window_link workspace id with
        | None ->
          [ heading window.name
          ; plain ~color:muted [%string "Window %{link.index#Int} · no panes"]
          ]
        | Some pane ->
          [ heading window.name
          ; plain
              ~color:muted
              [%string
                "Window %{link.index#Int} · active pane %{pane.index#Int} · \
                 %{pane.current_command}"]
          ]
          @ pane_preview_lines
              ~title:"Live window contents"
              ~subtitle:"Active pane · bottom of screen · read-only · refresh with r"
              model
              pane.id
              ~line_limit:(Int.max 1 (height - 7))))
  | Resource (Pane (_source, id)) ->
    (match Map.find workspace.panes id with
     | None -> [ heading "Pane ended" ]
     | Some pane ->
       let decision = decision_for (decisions_by_pane model.recovery) pane in
       [ heading [%string "Pane %{pane.index#Int}"]
       ; field "Typed ID" pane.id
       ; field "Working directory" pane.cwd
       ; field "Title" pane.title
       ; field "Observed command" pane.current_command
       ; field "Recovery" (Recovery.Action.label decision.action)
       ]
       @ pane_preview_lines model pane.id ~line_limit:preview_line_limit)
  | Resource (Application (_source, pane_id)) ->
    (match Map.find workspace.panes pane_id with
     | None -> [ heading "Application ended" ]
     | Some pane ->
       (decision_for (decisions_by_pane model.recovery) pane |> decision_lines)
       @ pane_preview_lines model pane.id ~line_limit:preview_line_limit)
  | Status ->
    let blocked = blocked_decisions model.recovery in
    let blocked_count = List.length blocked in
    let resumes = recovery_count model.recovery Recovery.Action.Resume in
    let restarts =
      recovery_count model.recovery Recovery.Action.Restart
      + recovery_count model.recovery Recovery.Action.Restart_clean
    in
    let application_health =
      if blocked_count = 0
      then
        [%string
          "PASS · %{resumes#Int} exact resume(s) · %{restarts#Int} safe restart(s) · 0 \
           blocked"]
      else [%string "WARN · %{blocked_count#Int} shell fallback(s) · details below"]
    in
    let application_warnings =
      List.concat_map blocked ~f:(fun decision ->
        let cause =
          match decision.rule_id with
          | Some "adapter:codex:missing-thread" -> "Codex has no durable thread ID."
          | Some _ | None -> decision.reason
        in
        [ plain
            ~color:amber
            [%string
              "Affected pane: %{pane_location workspace decision.pane_id} \
               (%{decision.observed})"]
        ; plain ~color:amber ("Cause: " ^ cause)
        ; plain ~color:amber "Recovery: shell only; the application will not resume."
        ])
    in
    let snapshot_lines =
      match model.snapshots with
      | Error error ->
        [ heading "Snapshots"
        ; field "Readiness" "WARN · snapshot inventory unavailable"
        ; plain ~color:amber (Error.to_string_hum error |> String.strip)
        ; plain ~color:muted "Press r to retry. Existing snapshot files are unchanged."
        ]
      | Ok catalog ->
        let native = native_snapshots catalog in
        let last_good = native_last_good catalog in
        let native_storage =
          List.fold native ~init:0L ~f:(fun total summary ->
            Int64.(total + summary.size_bytes))
        in
        [ heading "Snapshots"
        ; field
            "Readiness"
            (if Option.is_some last_good
             then "PASS · valid native recovery point available"
             else "WARN · no valid native recovery point; reboot recovery is unsafe")
        ; field
            "Native history"
            [%string "%{List.length native#Int} saved · rolling limit 10"]
        ; field
            "Last good"
            (Option.value_map last_good ~default:"none" ~f:(fun summary ->
               Snapshot.Id.display_time summary.id))
        ; field "Native storage" (bytes native_storage)
        ]
        @ warning_lines catalog.warnings
    in
    let automation_lines =
      match model.services with
      | Error error ->
        [ heading "Automation"
        ; field "Readiness" "WARN · service manager status unavailable"
        ; plain ~color:amber (Error.to_string_hum error |> String.strip)
        ; plain ~color:muted "Press r to retry. No automation settings were changed."
        ]
      | Ok status ->
        [ heading "Automation"
        ; field
            "Readiness"
            (if Service.equal_ownership status.ownership Managed
                && List.is_empty status.conflicts
             then "PASS · tmux-recovery manages save and login restore"
             else
               "WARN · "
               ^ Service.ownership_label status.ownership
               ^ "; inspect conflicts below")
        ; field "Periodic save" (component_health status.periodic_save)
        ]
        @ Option.value_map status.periodic_save.command ~default:[] ~f:(fun command ->
          [ field "Save command" command ])
        @ [ field
              "Next snapshot"
              (Option.value status.next_run ~default:"waiting for the first timer save")
          ; field "Login restore" (component_health status.login_restore)
          ]
        @ Option.value_map status.login_restore.command ~default:[] ~f:(fun command ->
          [ field "Restore command" command ])
        @ [ field
              "Last restore run"
              (Option.value status.last_restore ~default:"not recorded yet")
          ; field
              "Runtime version"
              (Option.value status.binary_version ~default:"unknown")
          ; field "Last result" (Option.value status.last_result ~default:"unavailable")
          ]
        @ List.map status.conflicts ~f:(fun conflict ->
          plain ~color:amber ("Active conflict: " ^ conflict))
        @ warning_lines status.warnings
    in
    [ heading "Status"
    ; plain ~color:muted "Recovery readiness, snapshot history, and automation."
    ; plain ""
    ; heading "Recovery"
    ; field
        "tmux"
        (if workspace.server.available
         then "PASS · server running"
         else "WARN · no tmux server; there is no live workspace to save")
    ; field
        "Workspace"
        [%string
          "PASS · %{Map.length workspace.sessions#Int} session(s) · %{Map.length \
           workspace.windows#Int} window(s) · %{Map.length workspace.panes#Int} pane(s)"]
    ; field "Applications" application_health
    ]
    @ application_warnings
    @ [ plain "" ]
    @ snapshot_lines
    @ [ plain "" ]
    @ automation_lines
    @ [ plain ""
      ; field "Mutation safety" "PASS · destructive operations require explicit approval"
      ; plain ~color:muted "Use the CLI for snapshot restore and automation changes."
      ]
;;

let render_detail model ~width ~height =
  let message =
    Option.value_map model.message ~default:[] ~f:(fun message ->
      [ plain ""; plain ~color:amber message ])
  in
  panel
    ~title:
      (let title =
         match model.selected with
         | Resource (Window_link _ | Pane _ | Application _) -> "PREVIEW"
         | Overview | Resource (Workspace _ | Session _) | Status -> "DETAIL"
       in
       if equal_focus model.focus Page then title ^ " ◀" else title)
    ~width
    ~height
    (detail_lines model ~height @ message)
;;

let render model { Dimensions.width; height } =
  let help =
    View.text
      ~attrs:[ Attr.fg muted; Attr.bg terminal_background ]
      " ↑/↓ move  ←/→ fold  enter open  tab focus  r refresh  q quit "
  in
  let body_height = Int.max 1 (height - 1) in
  let body =
    if width >= 84
    then (
      let navigation_width = Int.min 44 (width / 2) in
      let detail_width = Int.max 1 (width - navigation_width - 1) in
      let divider =
        List.init body_height ~f:(fun _ ->
          View.text
            ~attrs:[ Attr.fg terminal_foreground; Attr.bg terminal_background ]
            "│")
        |> View.vcat
      in
      View.hcat
        [ render_navigation model ~width:navigation_width ~height:body_height
        ; divider
        ; render_detail model ~width:detail_width ~height:body_height
        ])
    else (
      match model.focus with
      | Navigation -> render_navigation model ~width ~height:body_height
      | Page -> render_detail model ~width ~height:body_height)
  in
  View.vcat [ body; crop_to help ~width ~height:1 ]
;;

let app
  ?capture_pane
  ?reload
  ~service
  ~initial
  ?initial_recovery
  ~initial_snapshots
  ~initial_services
  ~exit
  ~dimensions
  (local_ graph)
  =
  let capture_pane =
    Option.value capture_pane ~default:(fun ~pane_id ->
      Effect.of_deferred_thunk (fun () -> App_recovery.capture_pane service ~pane_id))
  in
  let reload =
    Option.value reload ~default:(fun () ->
      Effect.of_deferred_thunk (fun () ->
        let open Deferred.Let_syntax in
        let%bind workspace = App_recovery.workspace service in
        let%bind recovery = App_recovery.plan service in
        let%bind snapshots = App_snapshot.list (App_snapshot.create ()) in
        let%map services = App_service.status (App_service.create ()) in
        workspace, recovery, snapshots, services))
  in
  let initial_recovery = Option.value initial_recovery ~default:(Recovery.plan initial) in
  let expanded = Page_ref.Set.of_list [ Resource (Workspace initial.Workspace.source) ] in
  let model, inject =
    Bonsai.state_machine
      ~default_model:
        { workspace = initial
        ; recovery = initial_recovery
        ; snapshots = initial_snapshots
        ; services = initial_services
        ; selected = Overview
        ; expanded
        ; focus = Navigation
        ; message = None
        ; preview_generation = 0
        ; pane_preview = No_preview
        }
      ~apply_action
      graph
  in
  let preview_target =
    let%arr model in
    pane_id_of_page model.workspace model.selected
    |> Option.map ~f:(fun pane_id -> pane_id, model.preview_generation)
  in
  Bonsai.Edge.on_change
    ~equal:[%equal: preview_request option]
    preview_target
    ~callback:
      (let%arr inject in
       function
       | None -> inject Clear_preview
       | Some ((pane_id, _) as request) ->
         let%bind.Effect () = inject (Preview_started request) in
         let%bind.Effect result = capture_pane ~pane_id in
         inject (Preview_finished (request, result)))
    graph;
  let refresh =
    let%arr inject in
    let%bind.Effect () = inject Refresh_started in
    let%bind.Effect workspace, recovery, snapshots, services = reload () in
    inject (Replace_data (workspace, recovery, snapshots, services))
  in
  let view =
    let%arr model and dimensions in
    render model dimensions
  in
  let handler =
    let%arr inject and refresh in
    fun (event : Event.t) ->
      match event with
      | Key_press { key = Arrow `Down; mods = [] } -> inject (Move 1)
      | Key_press { key = Arrow `Up; mods = [] } -> inject (Move (-1))
      | Key_press { key = Arrow `Right; mods = [] } -> inject Expand
      | Key_press { key = Arrow `Left; mods = [] } -> inject Collapse_or_parent
      | Key_press { key = Enter; mods = [] } -> inject Activate
      | Key_press { key = Tab; mods = [] } -> inject Toggle_focus
      | Key_press { key = ASCII 'r' | ASCII 'R'; mods = [] } -> refresh
      | Key_press { key = ASCII 'q' | ASCII 'Q'; mods = [] } -> exit ()
      | Key_press { key = ASCII ('c' | 'C'); mods = [ Ctrl ] } -> exit ()
      | _ -> Effect.Ignore
  in
  ~view, ~handler
;;

let command =
  Command.async_or_error
    ~summary:"Open the interactive tmux recovery navigator"
    (let%map_open.Command socket_name =
       flag
         "--socket"
         (optional string)
         ~doc:"NAME inspect a named tmux socket (the value passed to tmux -L)"
     in
     fun () ->
       let open Deferred.Let_syntax in
       let service = App_recovery.create ?socket_name () in
       let snapshots = App_snapshot.create () in
       let services = App_service.create () in
       let%bind initial = App_recovery.workspace service in
       match initial with
       | Error _ as error -> return error
       | Ok initial ->
         let%bind initial_recovery = App_recovery.plan service in
         (match initial_recovery with
          | Error _ as error -> return error
          | Ok initial_recovery ->
            let%bind initial_snapshots = App_snapshot.list snapshots in
            let%bind initial_services = App_service.status services in
            Bonsai_term.start_with_exit
              ~mouse:No_mouse_events
              (fun ~exit ~dimensions graph ->
                 app
                   ~service
                   ~initial
                   ~initial_recovery
                   ~initial_snapshots
                   ~initial_services
                   ~exit
                   ~dimensions
                   graph)))
;;
