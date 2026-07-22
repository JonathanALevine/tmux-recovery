open! Core
open Async
module Service = Tmux_recovery_domain.Service

type config = { directory : string }

val plan
  :  config
  -> source:string
  -> version:string
  -> Service.sync_plan Or_error.t Deferred.t

val apply : config -> Service.sync_plan -> unit Or_error.t Deferred.t
val rollback : config -> unit Or_error.t Deferred.t
