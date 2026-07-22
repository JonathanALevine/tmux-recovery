open! Core
open Async
module Domain = Tmux_recovery_domain.Native_snapshot
module Recovery = Tmux_recovery_domain.Recovery
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

type save_preparation =
  | Noop of string
  | Ready of Domain.t * Domain.save_plan

type save_result =
  | Save_noop of string
  | Saved of Snapshot.summary

type restore_result =
  { snapshot_id : Snapshot.Id.t
  ; session_count : int
  ; window_count : int
  ; pane_count : int
  ; application_warnings : string list
  }

type t =
  { native : Native_snapshot.config
  ; resurrect : Resurrect.config
  ; tmux : Tmux_adapter.config
  ; socket_name : string option
  ; tool_version : string
  ; now : unit -> Time_ns.t
  ; nonce : unit -> string
  ; legacy_only : bool
  ; codex : Codex.config
  }

let default_nonce =
  let state = lazy (Random.State.make_self_init ()) in
  fun () -> Random.State.bits (Lazy.force state) land 0x3fffffff |> sprintf "%08x"
;;

let create
  ?directory
  ?native_directory
  ?runtime_directory
  ?socket_name
  ?(tool_version = "dev")
  ?(now = Time_ns.now)
  ?(nonce = default_nonce)
  ?codex
  ()
  =
  let resurrect_default = Resurrect.default_config () in
  let resurrect =
    match directory with
    | None -> resurrect_default
    | Some directory -> { resurrect_default with directory }
  in
  let native_default = Native_snapshot.default_config () in
  let native =
    { native_default with
      directory = Option.value native_directory ~default:native_default.directory
    ; runtime_directory =
        Option.value runtime_directory ~default:native_default.runtime_directory
    }
  in
  { native
  ; resurrect
  ; tmux = Tmux_adapter.default_config ?socket_name ()
  ; socket_name
  ; tool_version
  ; now
  ; nonce
  ; legacy_only = Option.is_some directory && Option.is_none native_directory
  ; codex = Option.value codex ~default:(Codex.default_config ())
  }
;;

let merge_catalogs native legacy =
  let native_snapshots = native.Snapshot.snapshots in
  let legacy_snapshots = legacy.Snapshot.snapshots in
  { Snapshot.directory = native.directory
  ; directory_exists = native.directory_exists || legacy.directory_exists
  ; snapshots = Snapshot.sort_newest_first (native_snapshots @ legacy_snapshots)
  ; warnings = native.warnings @ legacy.warnings
  }
;;

let list t =
  if t.legacy_only
  then Resurrect.list t.resurrect
  else (
    let%map native = Native_snapshot.list t.native
    and legacy = Resurrect.list t.resurrect in
    Or_error.both native legacy
    |> Or_error.map ~f:(fun (native, legacy) -> merge_catalogs native legacy))
;;

let show t id =
  match Snapshot.Id.kind id with
  | Resurrect -> Resurrect.show t.resurrect id
  | Native ->
    let%map catalog = Native_snapshot.list t.native in
    Or_error.bind catalog ~f:(fun catalog ->
      match Snapshot.find catalog id with
      | Some summary -> Ok summary
      | None ->
        Or_error.error_s
          [%message "native snapshot not found" (Snapshot.Id.to_string id : string)])
;;

let without_bootstrap workspace =
  let sessions =
    Map.data workspace.Workspace.sessions
    |> List.filter ~f:(fun session -> not (String.equal session.name "restore-bootstrap"))
  in
  let session_ids =
    List.map sessions ~f:(fun session -> session.Workspace.Session.id)
    |> String.Set.of_list
  in
  let links =
    List.filter workspace.window_links ~f:(fun link ->
      Set.mem session_ids link.session_id)
  in
  let window_ids =
    List.map links ~f:(fun link -> link.Workspace.Window_link.window_id)
    |> String.Set.of_list
  in
  let windows =
    Map.data workspace.windows
    |> List.filter ~f:(fun window -> Set.mem window_ids window.Workspace.Window.id)
  and panes =
    Map.data workspace.panes
    |> List.filter ~f:(fun pane -> Set.mem window_ids pane.Workspace.Pane.window_id)
  in
  Workspace.create ~source:Live ~server:workspace.server sessions windows links panes
  |> Result.map_error ~f:(fun errors -> Error.of_string (String.concat errors ~sep:"; "))
;;

let prepare_save t ~trigger =
  let%bind observed = Tmux_adapter.observe t.tmux in
  match observed with
  | Error _ as error -> return error
  | Ok workspace when not workspace.server.available ->
    return (Ok (Noop "no tmux server is running"))
  | Ok observed ->
    (match without_bootstrap observed with
     | Error _ as error -> return error
     | Ok workspace when Map.is_empty workspace.sessions || Map.is_empty workspace.panes
       -> return (Ok (Noop "tmux contains no real sessions to save"))
     | Ok workspace ->
       let created_at = t.now () in
       (match Snapshot.Id.create_native ~created_at ~nonce:(t.nonce ()) with
        | Error _ as error -> return error
        | Ok id ->
          let%map capture = Codex.capture t.codex workspace in
          let codex_unresolved =
            Set.diff
              capture.detected_panes
              (Map.keys capture.resumes |> String.Set.of_list)
          in
          Domain.create
            ~codex_resumes:capture.resumes
            ~codex_unresolved
            ~id
            ~created_at
            ~trigger
            ~tool_version:t.tool_version
            workspace
          |> Or_error.map ~f:(fun snapshot ->
            Ready (snapshot, Domain.save_plan ~directory:t.native.directory snapshot))))
;;

let save t ~trigger =
  let%bind prepared = prepare_save t ~trigger in
  match prepared with
  | Error _ as error -> return error
  | Ok (Noop reason) -> return (Ok (Save_noop reason))
  | Ok (Ready (snapshot, _)) ->
    let%bind saved = Native_snapshot.save t.native ~socket_name:t.socket_name snapshot in
    (match saved with
     | Error _ as error -> return error
     | Ok summary ->
       let%map pruned = Native_snapshot.prune t.native ~now:(t.now ()) ~apply:true in
       let summary =
         match pruned with
         | Ok _ -> summary
         | Error error ->
           { summary with
             warnings =
               [%string
                 "snapshot committed, but retention failed: %{Error.to_string_hum error \
                  |> String.strip}"]
               :: summary.warnings
           }
       in
       Ok (Saved summary))
;;

let load_native t id = Native_snapshot.load t.native id
let resolve_native t selector = Native_snapshot.resolve t.native selector
let prune t ~apply = Native_snapshot.prune t.native ~now:(t.now ()) ~apply

let prepare_import_resurrect t legacy_id =
  let%map workspace = Resurrect.load_workspace t.resurrect legacy_id in
  let open Or_error.Let_syntax in
  let%bind workspace in
  let created_at = t.now () in
  let%bind id = Snapshot.Id.create_native ~created_at ~nonce:(t.nonce ()) in
  let%map snapshot =
    Domain.create ~id ~created_at ~trigger:Import ~tool_version:t.tool_version workspace
  in
  snapshot, Domain.save_plan ~directory:t.native.directory snapshot
;;

let import_resurrect t legacy_id =
  let open Deferred.Or_error.Let_syntax in
  let%bind snapshot, _plan = prepare_import_resurrect t legacy_id in
  Native_snapshot.save t.native ~socket_name:t.socket_name snapshot
;;

let prepare_restore t id =
  let%map snapshot = load_native t id in
  Or_error.map snapshot ~f:(Domain.restore_plan ?socket_name:t.socket_name)
;;

let restart_applications t snapshot restored decisions =
  Deferred.List.fold decisions ~init:[] ~f:(fun warnings decision ->
    match decision.Recovery.action, decision.executable with
    | (Shell_fallback | Blocked), _ | _, None -> return warnings
    | Resume, Some _ ->
      (match Map.find restored.Tmux_adapter.pane_ids decision.pane_id with
       | None ->
         return ([%string "pane mapping missing for %{decision.pane_id}"] :: warnings)
       | Some pane_id ->
         (match Map.find snapshot.Domain.codex_resumes decision.pane_id with
          | None ->
            return
              ([%string "Codex resume record missing for %{decision.pane_id}"] :: warnings)
          | Some resume ->
            let%bind validated = Codex.validate t.codex resume in
            (match validated with
             | Error error ->
               return
                 ([%string
                    "%{decision.pane_id}: %{Error.to_string_hum error |> String.strip}"]
                  :: warnings)
             | Ok launch ->
               let%map result =
                 Tmux_adapter.resume_codex
                   t.tmux
                   ~pane_id
                   ~cwd:launch.cwd
                   ~executable:launch.executable
                   ~thread_id:launch.thread_id
                   ~bypass_approvals:launch.bypass_approvals
               in
               (match result with
                | Ok () -> warnings
                | Error error ->
                  [%string
                    "%{decision.pane_id}: %{Error.to_string_hum error |> String.strip}"]
                  :: warnings))))
    | (Restart | Restart_clean), Some executable ->
      let pane = Map.find_exn snapshot.Domain.workspace.panes decision.pane_id in
      (match Map.find restored.Tmux_adapter.pane_ids decision.pane_id with
       | None ->
         return ([%string "pane mapping missing for %{decision.pane_id}"] :: warnings)
       | Some pane_id ->
         let%map result =
           Tmux_adapter.restart_approved t.tmux ~pane_id ~cwd:pane.cwd ~executable
         in
         (match result with
          | Ok () -> warnings
          | Error error ->
            [%string "%{decision.pane_id}: %{Error.to_string_hum error |> String.strip}"]
            :: warnings)))
;;

let restore_unlocked t id ~launch_applications =
  let open Deferred.Or_error.Let_syntax in
  let%bind snapshot = load_native t id in
  let%bind restored = Tmux_adapter.restore_workspace t.tmux snapshot.workspace in
  let%bind observed = Tmux_adapter.observe t.tmux in
  let%bind () =
    match Tmux_adapter.verify_restored ~saved:snapshot.workspace ~observed restored with
    | Ok () -> return ()
    | Error error ->
      Deferred.bind (Tmux_adapter.destroy_restored t.tmux restored) ~f:(fun () ->
        Deferred.return (Error error))
  in
  let expected_counts =
    ( Map.length snapshot.workspace.sessions
    , Map.length snapshot.workspace.windows
    , Map.length snapshot.workspace.panes )
  and observed_counts =
    Map.length observed.sessions, Map.length observed.windows, Map.length observed.panes
  in
  if not ([%equal: int * int * int] expected_counts observed_counts)
  then
    Deferred.Or_error.error_s
      [%message
        "restored workspace failed structural verification"
          (expected_counts : int * int * int)
          (observed_counts : int * int * int)]
  else (
    let decisions =
      Recovery.plan
        ~codex_resumes:snapshot.codex_resumes
        ~codex_detected:snapshot.codex_unresolved
        snapshot.workspace
    in
    let%bind application_warnings =
      if not launch_applications
      then return []
      else restart_applications t snapshot restored decisions.decisions |> Deferred.ok
    in
    let session_count, window_count, pane_count = observed_counts in
    return
      { snapshot_id = id
      ; session_count
      ; window_count
      ; pane_count
      ; application_warnings = List.rev application_warnings
      })
;;

let restore t id ~launch_applications =
  Native_snapshot.with_operation_lock t.native ~socket_name:t.socket_name (fun () ->
    restore_unlocked t id ~launch_applications)
;;
