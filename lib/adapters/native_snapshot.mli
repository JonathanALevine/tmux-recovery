open! Core
open Async
module Domain = Tmux_recovery_domain.Native_snapshot
module Snapshot = Tmux_recovery_domain.Snapshot

type config =
  { directory : string
  ; runtime_directory : string
  ; minimum_snapshots : int
  ; retention_days : int
  }

val default_config : unit -> config
val list : config -> Snapshot.catalog Or_error.t Deferred.t
val load : config -> Snapshot.Id.t -> Domain.t Or_error.t Deferred.t
val resolve : config -> string -> Snapshot.Id.t Or_error.t Deferred.t

val with_operation_lock
  :  config
  -> socket_name:string option
  -> (unit -> 'a Or_error.t Deferred.t)
  -> 'a Or_error.t Deferred.t

val save
  :  config
  -> socket_name:string option
  -> Domain.t
  -> Snapshot.summary Or_error.t Deferred.t

val prune_candidates
  :  config
  -> now:Time_ns.t
  -> Snapshot.catalog
  -> Snapshot.summary list

val prune
  :  config
  -> now:Time_ns.t
  -> apply:bool
  -> Snapshot.summary list Or_error.t Deferred.t
