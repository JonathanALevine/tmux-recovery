open! Core
open Async
module Domain = Tmux_recovery_domain.Native_snapshot
module Snapshot = Tmux_recovery_domain.Snapshot

type save_preparation =
  | Noop of string
  | Ready of Domain.t * Domain.save_plan

type save_result =
  | Save_noop of string
  | Saved of Snapshot.summary

type restore_result =
  { snapshot_id : Snapshot.Id.t
  ; session_count : int
  ; window_count : int
  ; pane_count : int
  ; application_warnings : string list
  }

type t

val create
  :  ?directory:string
  -> ?native_directory:string
  -> ?runtime_directory:string
  -> ?socket_name:string
  -> ?tool_version:string
  -> ?now:(unit -> Time_ns.t)
  -> ?nonce:(unit -> string)
  -> ?codex:Codex.config
  -> unit
  -> t

val list : t -> Snapshot.catalog Or_error.t Deferred.t
val show : t -> Snapshot.Id.t -> Snapshot.summary Or_error.t Deferred.t
val prepare_save : t -> trigger:Domain.Trigger.t -> save_preparation Or_error.t Deferred.t
val save : t -> trigger:Domain.Trigger.t -> save_result Or_error.t Deferred.t
val load_native : t -> Snapshot.Id.t -> Domain.t Or_error.t Deferred.t
val resolve_native : t -> string -> Snapshot.Id.t Or_error.t Deferred.t
val prune : t -> apply:bool -> Snapshot.summary list Or_error.t Deferred.t

val prepare_import_resurrect
  :  t
  -> Snapshot.Id.t
  -> (Domain.t * Domain.save_plan) Or_error.t Deferred.t

val import_resurrect : t -> Snapshot.Id.t -> Snapshot.summary Or_error.t Deferred.t
val prepare_restore : t -> Snapshot.Id.t -> Domain.restore_plan Or_error.t Deferred.t

val restore
  :  t
  -> Snapshot.Id.t
  -> launch_applications:bool
  -> restore_result Or_error.t Deferred.t
