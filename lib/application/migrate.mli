open! Core
open Async
module Domain = Tmux_recovery_domain.Migration

type t

val create : unit -> t
val plan : t -> Domain.plan Or_error.t Deferred.t
val apply : t -> Domain.plan -> string Or_error.t Deferred.t
val rollback : t -> Domain.plan -> unit Or_error.t Deferred.t
