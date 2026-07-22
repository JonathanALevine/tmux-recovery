open! Core

type asset_kind =
  | Script
  | Definition
[@@deriving compare, equal, sexp_of]

type asset =
  { path : string
  ; kind : asset_kind
  ; exists : bool
  ; sha256 : string option
  ; loaded : bool
  }
[@@deriving equal, sexp_of]

type plan =
  { manager : Service.manager
  ; backup_directory : string
  ; assets : asset list
  ; disable_commands : Service.command list
  ; managed_services : Service.plan
  }
[@@deriving equal, sexp_of]

val asset_kind_label : asset_kind -> string
val to_yojson : plan -> Yojson.Safe.t
