open! Core
open Async
module Domain = Tmux_recovery_domain.Migration
module Service = Tmux_recovery_domain.Service

type config =
  { home : string
  ; data_directory : string
  }

val default_config : unit -> config

val plan
  :  config
  -> manager:Service.manager
  -> managed_services:Service.plan
  -> now:Time_ns.t
  -> nonce:string
  -> Domain.plan Or_error.t Deferred.t

val create_backup : config -> Domain.plan -> unit Or_error.t Deferred.t
val run_commands : Service.command list -> unit Or_error.t Deferred.t
val active_legacy_enable_commands : config -> Service.command list Or_error.t Deferred.t
