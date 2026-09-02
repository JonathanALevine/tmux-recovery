open! Core
open Async
module Autonomy = Tmux_recovery_domain.Autonomy
module Domain_snapshot = Tmux_recovery_domain.Snapshot

type deps =
  { now : unit -> Time_ns.t
  ; observe : unit -> Tmux_recovery_domain.Workspace.t Or_error.t Deferred.t
  ; plan : Tmux_recovery_domain.Workspace.t -> Tmux_recovery_domain.Recovery.plan Or_error.t Deferred.t
  ; viewed : unit -> string list Or_error.t Deferred.t
  ; signature : window_id:string -> string Or_error.t Deferred.t
  ; server_identity : unit -> string Or_error.t Deferred.t
  ; snapshot_save : unit -> Domain_snapshot.summary Or_error.t Deferred.t
  ; close_window : window_id:string -> unit Or_error.t Deferred.t
  }

type t

type reconciled =
  { policy : Autonomy.config
  ; state : Autonomy.state
  ; fired : string option
  }

type tick_result =
  | Skipped of string
  | Reconciled of reconciled

val default_deps
  :  ?socket_name:string
  -> ?now:(unit -> Time_ns.t)
  -> ?snapshot_dir:string
  -> unit
  -> deps

val create
  :  ?socket_name:string
  -> ?store:Autonomy_store.t
  -> ?deps:deps
  -> ?now:(unit -> Time_ns.t)
  -> ?snapshot_dir:string
  -> unit
  -> t Or_error.t

val tick : t -> tick_result Or_error.t Deferred.t

type status_info =
  { policy : Autonomy.config
  ; paused : bool
  ; active : Autonomy.action list
  ; archived : Autonomy.action list
  ; candidates : (string * Time_ns.t option * bool) list
  ; audit : string list
  }

val status : t -> status_info Or_error.t Deferred.t

val configure
  :  t
  -> ?mode:Autonomy.Mode.t
  -> ?grace_seconds:int
  -> ?persistence_seconds:int
  -> ?snapshot_before_fire:bool
  -> unit
  -> unit Or_error.t Deferred.t

val cancel : t -> id:string -> unit Or_error.t Deferred.t
val pause : t -> unit Or_error.t Deferred.t
val resume : t -> unit Or_error.t Deferred.t
