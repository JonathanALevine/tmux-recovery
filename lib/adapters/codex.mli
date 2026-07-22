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

(** Capture the smallest durable resume record for each detected Codex pane. Provider
    failures degrade individual panes instead of failing the workspace save. *)
val capture : config -> Workspace.t -> capture Deferred.t

(** Revalidate the provider record and installed executable immediately before launch. *)
val validate : config -> Recovery.Codex_resume.t -> launch Or_error.t Deferred.t
