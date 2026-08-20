open! Core
open Async

(** Application-level recovery operations shared by the CLI and TUI. *)
type t

val create : ?socket_name:string -> ?codex:Codex.config -> unit -> t
val workspace : t -> Tmux_recovery_domain.Workspace.t Or_error.t Deferred.t
val capture_pane : t -> pane_id:string -> string list Or_error.t Deferred.t
val plan : t -> Tmux_recovery_domain.Recovery.plan Or_error.t Deferred.t

(** Close a single window (used by autonomous cleanup after a snapshot). *)
val close_window : t -> window_id:string -> unit Or_error.t Deferred.t
