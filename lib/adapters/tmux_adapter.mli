open! Core
open Async
module Workspace = Tmux_recovery_domain.Workspace

(** Explicit-argv adapter for observing tmux and capturing pane output. *)
type config =
  { executable : string
  ; socket_name : string option
  }

val default_config : ?socket_name:string -> unit -> config
val observe : config -> Workspace.t Or_error.t Deferred.t
val sanitize_capture_line : string -> string
val capture_pane : config -> pane_id:string -> string list Or_error.t Deferred.t

type restore_result =
  { session_ids : string String.Map.t
  ; window_ids : string String.Map.t
  ; pane_ids : string String.Map.t
  }

val restore_workspace : config -> Workspace.t -> restore_result Or_error.t Deferred.t

val verify_restored
  :  saved:Workspace.t
  -> observed:Workspace.t
  -> restore_result
  -> unit Or_error.t

val destroy_restored : config -> restore_result -> unit Deferred.t

val restart_approved
  :  config
  -> pane_id:string
  -> cwd:string
  -> executable:string
  -> unit Or_error.t Deferred.t

val resume_codex
  :  config
  -> pane_id:string
  -> cwd:string
  -> executable:string
  -> thread_id:string
  -> bypass_approvals:bool
  -> unit Or_error.t Deferred.t

val parse_rows
  :  socket_name:string option
  -> version:string option
  -> string list
  -> Workspace.t Or_error.t
