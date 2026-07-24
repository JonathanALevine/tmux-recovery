open! Core

type manager =
  | Launchd
  | Systemd
  | Unsupported of string
[@@deriving compare, equal, sexp_of]

type ownership =
  | Absent
  | Legacy
  | Managed
  | Drifted
[@@deriving compare, equal, sexp_of]

type activation =
  | Not_installed
  | Installed
  | Loaded
  | Disabled
  | Unknown
[@@deriving compare, equal, sexp_of]

type component =
  { activation : activation
  ; schedule : string option
  ; definition : string option
  ; command : string option
  }
[@@deriving equal, sexp_of]

type t =
  { manager : manager
  ; ownership : ownership
  ; periodic_save : component
  ; login_restore : component
  ; binary_path : string option
  ; binary_version : string option
  ; last_result : string option
  ; next_run : string option
  ; last_restore : string option
  ; conflicts : string list
  ; warnings : string list
  }
[@@deriving equal, sexp_of]

type managed_file =
  { path : string
  ; contents : string
  }
[@@deriving equal, sexp_of]

type command =
  { program : string
  ; arguments : string list
  }
[@@deriving equal, sexp_of]

type plan =
  { manager : manager
  ; stable_binary : string
  ; files : managed_file list
  ; enable_commands : command list
  ; disable_commands : command list
  ; conflicts : string list
  }
[@@deriving equal, sexp_of]

type sync_plan =
  { source : string
  ; destination : string
  ; current : string
  ; previous : string
  ; version : string
  ; sha256 : string
  }
[@@deriving equal, sexp_of]

val manager_label : manager -> string
val ownership_label : ownership -> string
val activation_label : activation -> string
val empty_component : component

val estimate_next_run
  :  now:Time_ns.t
  -> last_run:Time_ns.t
  -> interval_seconds:int
  -> Time_ns.t option

val to_yojson : t -> Yojson.Safe.t
val plan_to_yojson : plan -> Yojson.Safe.t
val sync_plan_to_yojson : sync_plan -> Yojson.Safe.t
