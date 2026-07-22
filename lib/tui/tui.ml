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
      | Snapshots
      | Snapshot of Snapshot.Id.t
      | Services
      | Doctor
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

let snapshot_badge (summary : Snapshot.summary) =
  [ Option.some_if summary.latest "latest"
  ; Option.some_if summary.last_good "last-good"
  ; (match summary.validity with
     | Valid -> None
     | Invalid _ -> Some "invalid")
  ; Option.some_if summary.manifest "manifest"
  ; Option.some_if summary.legacy "legacy"
  ]
  |> List.filter_opt
  |> function
  | [] -> None
  | badges -> Some (String.concat badges ~sep:" ")
;;

let snapshot_node (summary : Snapshot.summary) =
  { page = Page_ref.Snapshot summary.id
  ; label = Snapshot.Id.display_time summary.id
  ; badge = snapshot_badge summary
  ; children = []
  }
;;

let snapshot_navigation (snapshots : Snapshot.catalog Or_error.t) =
  match snapshots with
  | Error _ -> Some "unavailable", []
  | Ok catalog ->
    let invalid = List.count catalog.snapshots ~f:(Fn.non Snapshot.is_valid) in
    let badge =
      if invalid = 0
      then Int.to_string (List.length catalog.snapshots)
      else [%string "%{List.length catalog.snapshots#Int} · %{invalid#Int} invalid"]
    in
    Some badge, List.map catalog.snapshots ~f:snapshot_node
;;

let service_badge (services : Service.t Or_error.t) =
  match services with
  | Error _ -> Some "unavailable"
  | Ok status -> Some (Service.ownership_label status.ownership)
;;

let navigation (workspace : Workspace.t) recovery snapshots services =
  let decisions = decisions_by_pane recovery in
  let live_children =
    Workspace.ordered_sessions workspace |> List.map ~f:(session_node workspace decisions)
  in
  let snapshots_badge, snapshot_children = snapshot_navigation snapshots in
  [ { page = Overview; label = "Overview"; badge = None; children = [] }
  ; { page = Resource (Workspace workspace.source)
    ; label = "Sessions"
    ; badge = Some (if workspace.server.available then "online" else "offline")
    ; children = live_children
    }
  ; { page = Snapshots
    ; label = "Snapshots"
    ; badge = snapshots_badge
    ; children = snapshot_children
    }
  ; { page = Services
    ; label = "Automation"
    ; badge = service_badge services
    ; children = []
    }
  ; { page = Doctor; label = "Doctor"; badge = None; children = [] }
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
  | Snapshots ->
    (match model.snapshots with
     | Error _ -> red
     | Ok catalog when List.exists catalog.snapshots ~f:(Fn.non Snapshot.is_valid) ->
       amber
     | Ok _ -> cyan)
  | Snapshot id ->
    (match model.snapshots with
     | Error _ -> red
     | Ok catalog ->
       (match Snapshot.find catalog id with
        | Some summary when not (Snapshot.is_valid summary) -> red
        | Some summary when summary.latest || summary.last_good -> green
        | Some _ -> cyan
        | None -> red))
  | Services ->
    (match model.services with
     | Error _ -> red
     | Ok status ->
       (match status.ownership with
        | Service.Managed -> green
        | Legacy | Drifted -> amber
        | Absent -> muted))
  | Doctor -> cyan
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
      | Ok catalog -> Int.to_string (List.length catalog.snapshots)
      | Error _ -> "unavailable"
    in
    [ heading "tmux-recovery"
    ; plain "A conservative recovery control plane for tmux."
    ; plain ""
    ; field "tmux" (if workspace.server.available then "online" else "offline")
    ; field "Sessions" (Int.to_string (Map.length workspace.sessions))
    ; field "Canonical windows" (Int.to_string (Map.length workspace.windows))
    ; field "Panes" (Int.to_string (Map.length workspace.panes))
    ; field "Snapshots" snapshot_count
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
  | Snapshots ->
    (match model.snapshots with
     | Error error ->
       [ heading "Snapshots unavailable"
       ; plain ~color:amber (Error.to_string_hum error |> String.strip)
       ; plain ""
       ; plain ~color:muted "Press r to retry. No snapshot files were changed."
       ]
     | Ok catalog ->
       let newest =
         Snapshot.newest catalog
         |> Option.value_map ~default:"none" ~f:(fun item ->
           Snapshot.Id.display_time item.id)
       and last_good =
         Snapshot.last_good catalog
         |> Option.value_map ~default:"none" ~f:(fun item ->
           Snapshot.Id.to_string item.id)
       in
       [ heading "Snapshots"
       ; field "Directory" catalog.directory
       ; field
           "Directory health"
           (if catalog.directory_exists then "available" else "missing")
       ; field "Total" (Int.to_string (List.length catalog.snapshots))
       ; field "Valid" (Int.to_string (Snapshot.valid_count catalog))
       ; field "Newest" newest
       ; field "Last good" last_good
       ; field "Storage" (bytes (Snapshot.storage_bytes catalog))
       ; field "Retention" "native: keep 5 and 30 days · legacy: preserved"
       ; plain ""
       ; plain ~color:muted "Expand Snapshots to inspect immutable saved entries."
       ; plain ~color:muted "Captured pane contents and full commands are not displayed."
       ]
       @ warning_lines catalog.warnings)
  | Snapshot id ->
    (match model.snapshots with
     | Error error ->
       [ heading "Snapshot unavailable"; plain ~color:amber (Error.to_string_hum error) ]
     | Ok catalog ->
       (match Snapshot.find catalog id with
        | None -> [ heading "Snapshot no longer exists" ]
        | Some summary ->
          let badges = snapshot_badge summary |> Option.value ~default:"none" in
          let lines =
            [ heading (Snapshot.Id.display_time summary.id)
            ; field "Source ID" (Snapshot.Id.to_string summary.id)
            ; field "Validity" (Snapshot.validity_label summary.validity)
            ; field "Status" badges
            ; field "Sessions" (Int.to_string summary.session_count)
            ; field "Windows" (Int.to_string summary.window_count)
            ; field "Panes" (Int.to_string summary.pane_count)
            ; field "Size" (bytes summary.size_bytes)
            ; field "Process manifest" (if summary.manifest then "present" else "absent")
            ; field
                "Compatibility"
                (if summary.legacy then "legacy/upstream" else "managed")
            ; plain ""
            ; plain
                ~color:muted
                "Use snapshots restore --dry-run before approving restore."
            ]
          in
          let validity_lines =
            match summary.validity with
            | Valid -> [ plain ~color:green "Snapshot structure is valid." ]
            | Invalid errors -> warning_lines errors
          in
          lines @ validity_lines @ warning_lines summary.warnings))
  | Services ->
    (match model.services with
     | Error error ->
       [ heading "Automation unavailable"
       ; plain ~color:amber (Error.to_string_hum error |> String.strip)
       ; plain ""
       ; plain ~color:muted "Press r to retry. No automation settings were changed."
       ]
     | Ok status ->
       let component_status (component : Service.component) =
         match component.schedule with
         | None -> Service.activation_label component.activation
         | Some schedule ->
           Service.activation_label component.activation ^ " · " ^ schedule
       in
       [ heading "Automation"
       ; plain ~color:muted "Background snapshots and reboot recovery."
       ; plain ""
       ; field "Manager" (Service.manager_label status.manager)
       ; field "Ownership" (Service.ownership_label status.ownership)
       ; heading "Periodic snapshots"
       ; field "Status" (component_status status.periodic_save)
       ; field "Definition" (Option.value status.periodic_save.definition ~default:"none")
       ; heading "Restore after login"
       ; field "Status" (component_status status.login_restore)
       ; field "Definition" (Option.value status.login_restore.definition ~default:"none")
       ; heading "Runtime binary"
       ; field "Path" (Option.value status.binary_path ~default:"not detected")
       ; field "Version" (Option.value status.binary_version ~default:"unknown")
       ; heading "Recent result"
       ; field "Last result" (Option.value status.last_result ~default:"unavailable")
       ; field "Next run" (Option.value status.next_run ~default:"unavailable")
       ; field "Conflicts" (Int.to_string (List.length status.conflicts))
       ]
       @ List.map status.conflicts ~f:(fun conflict -> plain ~color:amber conflict)
       @ warning_lines status.warnings
       @ [ plain ~color:muted "Changes require reviewed CLI --approve flags." ])
  | Doctor ->
    let snapshot_health =
      match model.snapshots with
      | Error _ -> "WARN · unavailable"
      | Ok catalog ->
        (match Snapshot.last_good catalog with
         | Some _ -> "PASS · valid recovery point"
         | None -> "WARN · no valid recovery point")
    and application_health =
      if List.is_empty model.recovery.warnings then "PASS" else "WARN · review policy"
    and automation_health =
      match model.services with
      | Error _ -> "WARN · unavailable"
      | Ok status when Service.equal_ownership status.ownership Managed ->
        "PASS · managed"
      | Ok status -> "WARN · " ^ Service.ownership_label status.ownership
    in
    [ heading "Doctor"
    ; plain ~color:muted "Recovery readiness at a glance."
    ; plain ""
    ; field
        "tmux"
        (if workspace.server.available then "PASS · server running" else "WARN")
    ; field "workspace" "PASS · graph valid"
    ; field "snapshots" snapshot_health
    ; field "applications" application_health
    ; field "automation" automation_health
    ; field "mutation safety" "PASS · plan, approve, verify, rollback"
    ; plain ""
    ; plain ~color:muted "Run tmux-recovery doctor for full diagnostics."
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
         | Overview
         | Resource (Workspace _ | Session _)
         | Snapshots | Snapshot _ | Services | Doctor -> "DETAIL"
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
      " ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit "
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
      | Key_press { key = Arrow `Down | ASCII 'j'; mods = [] } -> inject (Move 1)
      | Key_press { key = Arrow `Up | ASCII 'k'; mods = [] } -> inject (Move (-1))
      | Key_press { key = Arrow `Right | ASCII 'l'; mods = [] } -> inject Expand
      | Key_press { key = Arrow `Left | ASCII 'h'; mods = [] } ->
        inject Collapse_or_parent
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
