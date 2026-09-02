open! Core
open Async
module Dom = Tmux_recovery_domain.Autonomy
module Autonomy = Dom
module Workspace = Tmux_recovery_domain.Workspace
module Recovery = Tmux_recovery_domain.Recovery
module Domain_snapshot = Tmux_recovery_domain.Snapshot
module Native_domain = Tmux_recovery_domain.Native_snapshot

type deps =
  { now : unit -> Time_ns.t
  ; observe : unit -> Workspace.t Or_error.t Deferred.t
  ; plan : Workspace.t -> Recovery.plan Or_error.t Deferred.t
  ; viewed : unit -> string list Or_error.t Deferred.t
  ; signature : window_id:string -> string Or_error.t Deferred.t
  ; server_identity : unit -> string Or_error.t Deferred.t
  ; snapshot_save : unit -> Domain_snapshot.summary Or_error.t Deferred.t
  ; close_window : window_id:string -> unit Or_error.t Deferred.t
  }

type t =
  { store : Autonomy_store.t
  ; deps : deps
  }

(** [let%bind] for ['a Or_error.t Deferred.t] chains (ppx_let desugars
    [let%bind] to [Let_syntax.bind]). *)
module Let_syntax = struct
  let bind = Deferred.Or_error.bind
end

let default_deps ?socket_name ?now ?snapshot_dir () =
  let tmux = Tmux_adapter.default_config ?socket_name () in
  let codex = Codex.default_config () in
  let snapshot =
    (match snapshot_dir with
     | Some root ->
       Snapshot.create
         ?socket_name
         ~codex:codex
         ~native_directory:(Filename.concat root "snapshots")
         ~runtime_directory:(Filename.concat root "runtime")
         ()
     | None -> Snapshot.create ?socket_name ~codex:codex ())
  in
  { now = Option.value now ~default:Time_ns.now
  ; observe = (fun () -> Tmux_adapter.observe tmux)
  ; plan =
      (fun workspace ->
       Deferred.map (Codex.capture codex workspace) ~f:(fun capture ->
         Ok
           (Recovery.plan
              ~codex_resumes:capture.resumes
              ~codex_detected:capture.detected_panes
              workspace)))
  ; viewed = (fun () -> Tmux_adapter.viewed_window_ids tmux)
  ; signature = (fun ~window_id -> Tmux_adapter.activity_signature tmux ~window_id)
  ; server_identity = (fun () -> Tmux_adapter.server_identity tmux)
  ; snapshot_save =
      (fun () ->
       Deferred.map
         (Snapshot.save snapshot ~trigger:Native_domain.Trigger.Manual)
         ~f:(fun result ->
           (match result with
            | Ok (Saved summary) -> Ok summary
            | Ok (Save_noop reason) -> Error (Error.of_string reason)
            | Error _ as error -> error)))
  ; close_window = (fun ~window_id -> Tmux_adapter.close_window tmux ~window_id)
  }
;;

let create ?socket_name ?store ?deps ?now ?snapshot_dir () =
  let store =
    (match store with
     | Some store -> Ok store
     | None -> Autonomy_store.create ())
  in
  Or_error.map store ~f:(fun store ->
    { store
    ; deps =
        Option.value ~default:(default_deps ?socket_name ?now ?snapshot_dir ()) deps
    })
;;

type reconciled =
  { policy : Autonomy.config
  ; state : Autonomy.state
  ; fired : string option
  }

type tick_result =
  | Skipped of string
  | Reconciled of reconciled

type status_info =
  { policy : Autonomy.config
  ; paused : bool
  ; active : Autonomy.action list
  ; archived : Autonomy.action list
  ; candidates : (string * Time_ns.t option * bool) list
  ; audit : string list
  }

(** Build a full target fingerprint for a window from a live workspace. *)
let target_of (workspace : Workspace.t) ~window_id ~session_id ~server_identity
  : Autonomy.target option =
  (match Map.find workspace.windows window_id with
   | None -> None
   | Some window ->
     let panes =
       Workspace.panes_for_window workspace ~window_id
       |> List.map ~f:(fun pane -> pane.Workspace.Pane.id, pane.current_command)
       |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)
     in
     Some
       { Autonomy.window_id = window_id
       ; session_id
       ; server_identity
       ; window_name = window.name
       ; window_layout = window.layout
       ; panes
       })
;;

(** Build one full candidate from a live workspace. A transient observation
    error skips the window for this tick. *)
let candidate_of t (workspace : Workspace.t) ~window_id ~session_id ~reason
  : Autonomy.candidate option Deferred.t =
  Deferred.map
    (Deferred.bind (t.deps.signature ~window_id) ~f:(fun sig_result ->
       Deferred.bind (t.deps.server_identity ()) ~f:(fun id_result ->
         Deferred.return (Ok (sig_result, id_result)))))
    ~f:(fun both ->
      (match both with
       | Error _ -> None
       | Ok (sig_result, id_result) ->
         (match sig_result, id_result with
          | Ok signature, Ok server_identity ->
            (match target_of workspace ~window_id ~session_id ~server_identity with
             | None -> None
             | Some target -> (Some { target; reason; signature } : Autonomy.candidate option))
          | _ -> None)))
;;

(** Fresh observation of one candidate window: detect + signature + identity.
    An error means the window is no longer eligible or disappeared. *)
let observe_candidate t ~window_id =
  let%bind workspace = t.deps.observe () in
  let%bind plan = t.deps.plan workspace in
  let%bind viewed = t.deps.viewed () in
  let detected = Autonomy.detect ~workspace ~recovery:plan ~viewed in
  (match List.find detected ~f:(fun (id, _, _) -> String.equal id window_id) with
   | None ->
     Deferred.return
       (Error
          (Error.of_string
             "window no longer eligible (no longer blocked, now viewed, or gone)"))
   | Some (id, detected_session_id, detected_reason) ->
     let%bind signature = t.deps.signature ~window_id:id in
     let%bind server_identity = t.deps.server_identity () in
     (match target_of workspace ~window_id:id ~session_id:detected_session_id ~server_identity with
      | None ->
        Deferred.return
          (Error (Error.of_string "window disappeared during the eligibility recheck"))
      | Some target ->
        Deferred.return (Ok ({ target; reason = detected_reason; signature } : Autonomy.candidate))))
;;

(** Live fire for one due action: fresh eligibility recheck, snapshot (when
    configured), a second fresh recheck, then close the exact window. Recheck
    failures become abort outcomes; the action always reaches a terminal state. *)
let fire_live t ~now state (action : Autonomy.action)
  : Autonomy.state Or_error.t Deferred.t =
  Deferred.bind (observe_candidate t ~window_id:action.window_id) ~f:(fun fresh_result ->
    (match fresh_result with
     | Error e ->
       Deferred.return
         (Ok
            (Autonomy.abort_fire ~now ~id:action.id ~reason:(Error.to_string_hum e) state))
     | Ok fresh ->
       (match Autonomy.target_matches action fresh with
        | Error e ->
          Deferred.return
            (Ok
               (Autonomy.abort_fire ~now ~id:action.id ~reason:(Error.to_string_hum e) state))
        | Ok () ->
          (* Snapshot before firing; a concrete snapshot ID is required to proceed. *)
          let%bind snapshot_id =
            if state.config.snapshot_before_fire
            then
              Deferred.map (t.deps.snapshot_save ()) ~f:(fun result ->
                (match result with
                 | Ok summary -> Ok (Some (Domain_snapshot.Id.to_string summary.id))
                 | Error _ -> Ok None))
            else Deferred.return (Ok None)
          in
          (match snapshot_id with
           | None ->
             Deferred.return
               (Ok
                  (Autonomy.abort_fire
                     ~now
                     ~id:action.id
                     ~reason:"snapshot was not available; the window was not closed"
                     state))
           | Some snapshot_id ->
             (* Second fresh eligibility check, after the snapshot. *)
             Deferred.bind (observe_candidate t ~window_id:action.window_id) ~f:(fun fresh2_result ->
               (match fresh2_result with
                | Error e ->
                  Deferred.return
                    (Ok
                       (Autonomy.abort_fire
                          ~now
                          ~id:action.id
                          ~reason:(Error.to_string_hum e)
                          state))
                | Ok fresh2 ->
                  (match Autonomy.target_matches action fresh2 with
                   | Error e ->
                     Deferred.return
                       (Ok
                          (Autonomy.abort_fire
                             ~now
                             ~id:action.id
                             ~reason:(Error.to_string_hum e)
                             state))
                   | Ok () ->
                     Deferred.bind
                       (t.deps.close_window ~window_id:action.window_id)
                       ~f:(fun close_result ->
                         Deferred.return
                           (match close_result with
                            | Ok () ->
                              Ok
                                (Autonomy.apply_fire
                                   ~now
                                   ~id:action.id
                                   ~snapshot_id
                                   ~dry_run:false
                                   ~note:"closed"
                                   state)
                            | Error e ->
                              Ok
                                (Autonomy.fail_fire
                                   ~now
                                   ~id:action.id
                                   ~reason:(Error.to_string_hum e)
                                   state))))))))))
;;

let tick t =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind policy = Deferred.return (Autonomy_store.load_policy t.store) in
    let%bind state0 = Deferred.return (Autonomy_store.load_state t.store) in
    let now0 = t.deps.now () in
    let state = Autonomy.with_config ~now:now0 policy state0 in
    (match state.config.mode with
     | Autonomy.Mode.Off -> Deferred.return (Ok (Skipped "autonomy is off"))
     | _ ->
       (match state.paused with
        | true -> Deferred.return (Ok (Skipped "autonomy is paused"))
        | false ->
          let%bind workspace = t.deps.observe () in
          let%bind plan = t.deps.plan workspace in
          let%bind viewed = t.deps.viewed () in
          let detected = Autonomy.detect ~workspace ~recovery:plan ~viewed in
          let%bind candidates =
            Deferred.map
              (Deferred.List.map detected ~how:`Sequential
                 ~f:(fun (window_id, session_id, reason) ->
                   candidate_of t workspace ~window_id ~session_id ~reason))
              ~f:(fun results -> Ok (List.filter_map results ~f:Fn.id))
          in
          let now = t.deps.now () in
          let state = Autonomy.tick ~now ~candidates state in
          let%bind state, fired =
            (match List.hd (Autonomy.due ~now state) with
             | None -> Deferred.return (Ok (state, None))
             | Some action ->
               (match state.config.mode with
                | Autonomy.Mode.Dry_run ->
                  let state =
                    Autonomy.apply_fire
                      ~now
                      ~id:action.id
                      ~dry_run:true
                      ~note:"dry-run; the window would be closed"
                      state
                  in
                  Deferred.return (Ok (state, Some action.id))
                | Autonomy.Mode.Live ->
                  Deferred.Or_error.map (fire_live t ~now state action) ~f:(fun state ->
                    state, Some action.id)
                | Autonomy.Mode.Off -> Deferred.return (Ok (state, None))))
          in
          let%bind () = Deferred.return (Autonomy_store.save_state t.store state) in
          let%bind () = Deferred.return (Autonomy_store.sync_audit t.store (Autonomy.audit state)) in
          Deferred.return (Ok (Reconciled { policy = state.config; state; fired })))))
;;

let status t =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind policy = Deferred.return (Autonomy_store.load_policy t.store) in
    let loaded = Deferred.return (Autonomy_store.load_state t.store) in
    let%bind state = loaded in
    Deferred.return
      (Ok
         { policy
         ; paused = Autonomy.paused state
         ; active = Autonomy.active state
         ; archived = state.archived
         ; candidates = Autonomy.candidates state
         ; audit = Autonomy.audit_lines state
         }))
;;

let configure t ?mode ?grace_seconds ?persistence_seconds ?snapshot_before_fire () =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind policy = Deferred.return (Autonomy_store.load_policy t.store) in
    let config : Autonomy.config =
      { mode = Option.value mode ~default:policy.mode
      ; grace_seconds = Option.value grace_seconds ~default:policy.grace_seconds
      ; persistence_seconds =
          Option.value persistence_seconds ~default:policy.persistence_seconds
      ; snapshot_before_fire =
          Option.value snapshot_before_fire ~default:policy.snapshot_before_fire
      }
    in
    let%bind () = Deferred.return (Autonomy_store.save_policy t.store config) in
    Deferred.return (Ok ()))
;;

let cancel t ~id =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind state = Deferred.return (Autonomy_store.load_state t.store) in
    let state = Autonomy.cancel ~now:(t.deps.now ()) ~id state in
    let%bind () = Deferred.return (Autonomy_store.save_state t.store state) in
    let%bind () = Deferred.return (Autonomy_store.sync_audit t.store (Autonomy.audit state)) in
    Deferred.return (Ok ()))
;;

let pause t =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind state = Deferred.return (Autonomy_store.load_state t.store) in
    let state = Autonomy.pause ~now:(t.deps.now ()) state in
    let%bind () = Deferred.return (Autonomy_store.save_state t.store state) in
    let%bind () = Deferred.return (Autonomy_store.sync_audit t.store (Autonomy.audit state)) in
    Deferred.return (Ok ()))
;;

let resume t =
  Autonomy_store.with_lock_async t.store ~f:(fun () ->
      let%bind state = Deferred.return (Autonomy_store.load_state t.store) in
    let state = Autonomy.resume ~now:(t.deps.now ()) state in
    let%bind () = Deferred.return (Autonomy_store.save_state t.store state) in
    let%bind () = Deferred.return (Autonomy_store.sync_audit t.store (Autonomy.audit state)) in
    Deferred.return (Ok ()))
;;
