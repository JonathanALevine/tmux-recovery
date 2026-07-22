open! Core

module Source : sig
  type t =
    | Live
    | Snapshot of string
  [@@deriving compare, equal, sexp_of]

  val label : t -> string
end

module Server : sig
  type t =
    { available : bool
    ; socket : string option
    ; version : string option
    }
  [@@deriving equal, sexp_of]
end

module Session : sig
  type t =
    { id : string
    ; name : string
    ; attached : bool
    }
  [@@deriving equal, sexp_of]
end

module Window : sig
  type t =
    { id : string
    ; name : string
    ; layout : string
    }
  [@@deriving equal, sexp_of]
end

module Window_link : sig
  type t =
    { id : string
    ; session_id : string
    ; window_id : string
    ; index : int
    ; active : bool
    }
  [@@deriving equal, sexp_of]
end

module Pane : sig
  type t =
    { id : string
    ; window_id : string
    ; index : int
    ; active : bool
    ; title : string
    ; cwd : string
    ; current_command : string
    ; pid : int option
    ; tty : string option
    }
  [@@deriving equal, sexp_of]
end

type t =
  { source : Source.t
  ; server : Server.t
  ; sessions : Session.t String.Map.t
  ; windows : Window.t String.Map.t
  ; window_links : Window_link.t list
  ; panes : Pane.t String.Map.t
  }
[@@deriving equal, sexp_of]

val empty_live : ?socket:string -> ?version:string -> unit -> t

val create
  :  source:Source.t
  -> server:Server.t
  -> Session.t list
  -> Window.t list
  -> Window_link.t list
  -> Pane.t list
  -> (t, string list) Result.t

val validate : t -> (unit, string list) Result.t
val ordered_sessions : t -> Session.t list
val links_for_session : t -> session_id:string -> Window_link.t list
val panes_for_window : t -> window_id:string -> Pane.t list
val linked_session_count : t -> window_id:string -> int
val to_yojson : t -> Yojson.Safe.t
