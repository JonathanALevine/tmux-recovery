open! Core
open Bonsai_term

val app
  :  ?capture_pane:(pane_id:string -> string list Or_error.t Effect.t)
  -> ?reload:
       (unit
        -> (Tmux_recovery_domain.Workspace.t Or_error.t
           * Tmux_recovery_domain.Recovery.plan Or_error.t
           * Tmux_recovery_domain.Snapshot.catalog Or_error.t
           * Tmux_recovery_domain.Service.t Or_error.t)
             Effect.t)
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
