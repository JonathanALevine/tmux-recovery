open! Core
open Bonsai_term
module Recovery = Tmux_recovery_domain.Recovery
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

type reload_result =
  Workspace.t Or_error.t
  * Recovery.plan Or_error.t
  * Snapshot.catalog Or_error.t
  * Service.t Or_error.t

(** Build the TUI with an injected [reload] so tests can observe and control refresh
    concurrency. *)
val make_app_with_reload
  :  reload:(unit -> reload_result Effect.t)
  -> dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val warning_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val empty_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val unavailable_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t
