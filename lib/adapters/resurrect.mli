open! Core
open Async
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

type config =
  { directory : string
  ; manifest_directory : string
  }

val default_config : unit -> config
val list : config -> Snapshot.catalog Or_error.t Deferred.t
val show : config -> Snapshot.Id.t -> Snapshot.summary Or_error.t Deferred.t
val load_workspace : config -> Snapshot.Id.t -> Workspace.t Or_error.t Deferred.t
val workspace_of_lines : id:Snapshot.Id.t -> string list -> Workspace.t Or_error.t

val summarize_lines
  :  id:Snapshot.Id.t
  -> created_at:Time_ns.t
  -> size_bytes:int64
  -> latest:bool
  -> manifest:bool
  -> string list
  -> Snapshot.summary

val catalog_of_summaries
  :  directory:string
  -> directory_exists:bool
  -> current:Snapshot.Id.t option
  -> warnings:string list
  -> Snapshot.summary list
  -> Snapshot.catalog
