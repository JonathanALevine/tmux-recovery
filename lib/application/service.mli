open! Core
open Async

type platform =
  | Auto
  | Macos
  | Linux
  | Other of string

type t

val create
  :  ?platform:platform
  -> ?launch_agents_directory:string
  -> ?systemd_unit_directory:string
  -> ?data_directory:string
  -> ?state_directory:string
  -> unit
  -> t

val status : t -> Tmux_recovery_domain.Service.t Or_error.t Deferred.t
val plan : t -> Tmux_recovery_domain.Service.plan Or_error.t Deferred.t

val sync_plan
  :  t
  -> source:string
  -> version:string
  -> Tmux_recovery_domain.Service.sync_plan Or_error.t Deferred.t

val sync : t -> Tmux_recovery_domain.Service.sync_plan -> unit Or_error.t Deferred.t
val rollback : t -> unit Or_error.t Deferred.t
val enable : t -> Tmux_recovery_domain.Service.plan -> unit Or_error.t Deferred.t
val disable : t -> Tmux_recovery_domain.Service.plan -> unit Or_error.t Deferred.t
