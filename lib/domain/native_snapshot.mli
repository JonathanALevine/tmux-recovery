open! Core

module Trigger : sig
  type t =
    | Manual
    | Timer
    | Shutdown
    | Login
    | Import
  [@@deriving compare, equal, sexp_of]

  val of_string : string -> t Or_error.t
  val to_string : t -> string
end

type t =
  { id : Snapshot.Id.t
  ; created_at : Time_ns.t
  ; trigger : Trigger.t
  ; tool_version : string
  ; workspace : Workspace.t
  ; codex_resumes : Recovery.Codex_resume.t String.Map.t
  ; codex_unresolved : String.Set.t
  }
[@@deriving equal, sexp_of]

type save_plan =
  { id : Snapshot.Id.t
  ; directory : string
  ; trigger : Trigger.t
  ; session_count : int
  ; window_count : int
  ; pane_count : int
  }
[@@deriving equal, sexp_of]

type restore_plan =
  { snapshot : t
  ; socket_name : string option
  ; recovery : Recovery.plan
  }
[@@deriving equal, sexp_of]

val create
  :  ?codex_resumes:Recovery.Codex_resume.t String.Map.t
  -> ?codex_unresolved:String.Set.t
  -> id:Snapshot.Id.t
  -> created_at:Time_ns.t
  -> trigger:Trigger.t
  -> tool_version:string
  -> Workspace.t
  -> t Or_error.t

val save_plan : directory:string -> t -> save_plan
val restore_plan : ?socket_name:string -> t -> restore_plan
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> t Or_error.t
val save_plan_to_yojson : save_plan -> Yojson.Safe.t
val restore_plan_to_yojson : restore_plan -> Yojson.Safe.t
