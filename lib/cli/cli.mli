open! Core

(** Command-line interface and versioned output surface. *)
val version : string

(** UTC build timestamp (ISO 8601) captured when the library was compiled. *)
val build_time : string

val commands : (string * Command.t) list
