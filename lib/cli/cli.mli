open! Core

(** Command-line interface and versioned output surface. *)
val version : string

val commands : (string * Command.t) list
