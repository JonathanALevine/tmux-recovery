open! Core

module Id : sig
  type t = private string [@@deriving compare, equal, sexp_of]

  type kind =
    | Native
    | Resurrect
  [@@deriving compare, equal, sexp_of]

  val of_string : string -> t Or_error.t
  val create_native : created_at:Time_ns.t -> nonce:string -> t Or_error.t
  val kind : t -> kind
  val to_string : t -> string
  val display_time : t -> string
end

type validity =
  | Valid
  | Invalid of string list
[@@deriving compare, equal, sexp_of]

type summary =
  { id : Id.t
  ; created_at : Time_ns.t
  ; size_bytes : int64
  ; latest : bool
  ; last_good : bool
  ; validity : validity
  ; warnings : string list
  ; session_count : int
  ; window_count : int
  ; pane_count : int
  ; manifest : bool
  ; legacy : bool
  }
[@@deriving equal, sexp_of]

type catalog =
  { directory : string
  ; directory_exists : bool
  ; snapshots : summary list
  ; warnings : string list
  }
[@@deriving equal, sexp_of]

val validity_label : validity -> string
val is_valid : summary -> bool
val find : catalog -> Id.t -> summary option
val valid_count : catalog -> int
val storage_bytes : catalog -> int64
val newest : catalog -> summary option
val last_good : catalog -> summary option
val sort_newest_first : summary list -> summary list
val summary_to_yojson : summary -> Yojson.Safe.t
val catalog_to_yojson : catalog -> Yojson.Safe.t
