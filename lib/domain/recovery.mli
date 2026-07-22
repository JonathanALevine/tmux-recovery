open! Core

module Action : sig
  type t =
    | Shell_fallback
    | Restart
    | Restart_clean
    | Resume
    | Blocked
  [@@deriving compare, equal, sexp_of]

  val label : t -> string
end

module Codex_resume : sig
  type t =
    { thread_id : string
    ; cwd : string
    ; bypass_approvals : bool
    }
  [@@deriving equal, sexp_of]

  val create : thread_id:string -> cwd:string -> bypass_approvals:bool -> t Or_error.t
  val to_yojson : t -> Yojson.Safe.t
  val of_yojson : Yojson.Safe.t -> t Or_error.t
end

type decision =
  { pane_id : string
  ; observed : string
  ; action : Action.t
  ; executable : string option
  ; argv : string list
  ; fidelity : string
  ; reason : string
  ; rule_id : string option
  }
[@@deriving equal, sexp_of]

type plan =
  { source : Workspace.Source.t
  ; decisions : decision list
  ; warnings : string list
  }
[@@deriving equal, sexp_of]

val classify
  :  ?codex_resume:Codex_resume.t
  -> ?codex_detected:bool
  -> Workspace.Pane.t
  -> decision

val plan
  :  ?codex_resumes:Codex_resume.t String.Map.t
  -> ?codex_detected:String.Set.t
  -> Workspace.t
  -> plan

val counts : plan -> (Action.t * int) list
val to_yojson : plan -> Yojson.Safe.t
