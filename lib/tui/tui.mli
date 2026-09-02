open! Core
open Bonsai_term
module Autonomy_runner = Tmux_recovery_application.Autonomy

(** The interactive navigator. The autonomy pipeline itself is service-owned and
    disk-persisted; the TUI is a viewer and controller over it. [autonomy_runner]
    is the application runner backed by the persistent store: refreshes reconcile
    the pipeline (one tick) and the view shows the persisted policy, the eligibility
    funnel, pending actions, and the recent audit. [c] cancels the oldest pending
    action and [p] pauses or resumes the pipeline. *)
val app
  :  ?capture_pane:(pane_id:string -> string list Or_error.t Effect.t)
  -> ?reload:
       (unit
        -> (Tmux_recovery_domain.Workspace.t Or_error.t
           * Tmux_recovery_domain.Recovery.plan Or_error.t
           * Tmux_recovery_domain.Snapshot.catalog Or_error.t
           * Tmux_recovery_domain.Service.t Or_error.t)
             Effect.t)
  -> autonomy_runner:Autonomy_runner.t
  -> initial_autonomy:Autonomy_runner.status_info
  -> service:Tmux_recovery_application.Recovery.t
  -> initial:Tmux_recovery_domain.Workspace.t
  -> ?initial_recovery:Tmux_recovery_domain.Recovery.plan
  -> initial_snapshots:Tmux_recovery_domain.Snapshot.catalog Or_error.t
  -> initial_services:Tmux_recovery_domain.Service.t Or_error.t
  -> exit:(unit -> unit Effect.t)
  -> dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val command : Command.t
