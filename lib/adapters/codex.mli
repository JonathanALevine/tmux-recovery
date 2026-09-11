open! Core
open Async
module Recovery = Tmux_recovery_domain.Recovery
module Workspace = Tmux_recovery_domain.Workspace

type config

type launch =
  { executable : string
  ; cwd : string
  ; thread_id : string
  ; bypass_approvals : bool
  }

type capture =
  { resumes : Recovery.Codex_resume.t String.Map.t
  ; detected_panes : String.Set.t
  ; observation_errors : Error.t list
  (** Provider failures, distinct from a successful lookup with no thread. *)
  }

val create
  :  codex_home:string
  -> executable_candidates:string list
  -> process_executable:string
  -> config

val default_config : unit -> config

(** Read-only provider queries exposed for synthetic database tests. *)
val lookup_latest_for_cwd
  :  config
  -> cwd:string
  -> Recovery.Codex_resume.t option Or_error.t

val lookup_for_processes
  :  ?explicit_thread_id:string
  -> ?allow_cwd_fallback:bool
  -> config
  -> pids:int list
  -> fallback_cwd:string
  -> Recovery.Codex_resume.t option Or_error.t

val explicit_resume_thread_id : string -> string option
val thread_locks_by_pid : codex_home:string -> string list -> string Int.Map.t

(** Capture the smallest durable resume record for each detected Codex pane. Provider
    failures are retained in [observation_errors] so callers can reject unsafe saves. *)
val capture : config -> Workspace.t -> capture Deferred.t

(** Resolve a captured process/open-file inventory. Shared by live capture and
    deterministic provider regression tests. Database reads are synchronous. *)
val capture_from_observations
  :  config
  -> Workspace.t
  -> processes:string list Or_error.t
  -> open_files:string list Or_error.t
  -> capture

(** Revalidate the provider record and installed executable immediately before launch. *)
val validate : config -> Recovery.Codex_resume.t -> launch Or_error.t Deferred.t
