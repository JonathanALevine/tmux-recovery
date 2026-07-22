open! Core

module Id = struct
  module T = struct
    type t = string [@@deriving compare, equal, sexp_of]
  end

  include T

  type kind =
    | Native
    | Resurrect
  [@@deriving compare, equal, sexp_of]

  let resurrect_prefix = "tmux_resurrect_"
  let resurrect_suffix = ".txt"
  let native_prefix = "tmux_recovery_"
  let native_suffix = ".snapshot"

  let valid_timestamp value =
    String.length value = 15
    && Char.equal value.[8] 'T'
    && String.for_alli value ~f:(fun index character ->
      index = 8 || Char.is_digit character)
  ;;

  let valid_native_body value =
    match String.rsplit2 value ~on:'_' with
    | Some (nanoseconds, nonce) ->
      (not (String.is_empty nanoseconds))
      && String.for_all nanoseconds ~f:Char.is_digit
      && String.length nonce = 8
      && String.for_all nonce ~f:Char.is_hex_digit
      && Option.is_some (Int63.of_string_opt nanoseconds)
    | None -> false
  ;;

  let kind_of_string value =
    if String.is_prefix value ~prefix:native_prefix
       && String.is_suffix value ~suffix:native_suffix
    then (
      let body =
        String.sub
          value
          ~pos:(String.length native_prefix)
          ~len:
            (String.length value
             - String.length native_prefix
             - String.length native_suffix)
      in
      Option.some_if (valid_native_body body) Native)
    else if String.is_prefix value ~prefix:resurrect_prefix
            && String.is_suffix value ~suffix:resurrect_suffix
    then (
      let timestamp =
        String.sub
          value
          ~pos:(String.length resurrect_prefix)
          ~len:
            (String.length value
             - String.length resurrect_prefix
             - String.length resurrect_suffix)
      in
      Option.some_if (valid_timestamp timestamp) Resurrect)
    else None
  ;;

  let of_string value =
    match kind_of_string value with
    | Some _ -> Ok value
    | None ->
      Or_error.error_s
        [%message
          "invalid snapshot ID"
            (value : string)
            ~expected:
              "tmux_recovery_<unix-nanoseconds>_<8-hex>.snapshot or +               \
               tmux_resurrect_YYYYMMDDTHHMMSS.txt"]
  ;;

  let kind t = Option.value_exn (kind_of_string t)

  let create_native ~created_at ~nonce =
    let nonce = String.lowercase nonce in
    if String.length nonce <> 8 || not (String.for_all nonce ~f:Char.is_hex_digit)
    then
      Or_error.error_s [%message "native snapshot nonce must be eight hex digits" nonce]
    else
      Ok
        [%string
          "%{native_prefix}%{Time_ns.to_int63_ns_since_epoch \
           created_at#Int63}_%{nonce}%{native_suffix}"]
  ;;

  let to_string t = t

  let display_time t =
    match kind t with
    | Native ->
      let body =
        String.sub
          t
          ~pos:(String.length native_prefix)
          ~len:
            (String.length t - String.length native_prefix - String.length native_suffix)
      in
      let nanoseconds = String.rsplit2_exn body ~on:'_' |> fst |> Int63.of_string in
      Time_ns.of_int63_ns_since_epoch nanoseconds |> Time_ns.to_string_utc
    | Resurrect ->
      let timestamp =
        String.sub
          t
          ~pos:(String.length resurrect_prefix)
          ~len:
            (String.length t
             - String.length resurrect_prefix
             - String.length resurrect_suffix)
      in
      [%string
        "%{String.sub timestamp ~pos:0 ~len:4}-%{String.sub timestamp ~pos:4 \
         ~len:2}-%{String.sub timestamp ~pos:6 ~len:2} %{String.sub timestamp ~pos:9 \
         ~len:2}:%{String.sub timestamp ~pos:11 ~len:2}:%{String.sub timestamp ~pos:13 \
         ~len:2}"]
  ;;
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

let validity_label = function
  | Valid -> "valid"
  | Invalid _ -> "invalid"
;;

let is_valid summary =
  match summary.validity with
  | Valid -> true
  | Invalid _ -> false
;;

let sort_newest_first summaries =
  List.sort summaries ~compare:(fun left right ->
    match Time_ns.compare right.created_at left.created_at with
    | 0 -> Id.compare right.id left.id
    | order -> order)
;;

let find catalog id = List.find catalog.snapshots ~f:(fun item -> Id.equal item.id id)
let valid_count catalog = List.count catalog.snapshots ~f:is_valid

let storage_bytes catalog =
  List.fold catalog.snapshots ~init:0L ~f:(fun total item ->
    Int64.(total + item.size_bytes))
;;

let newest catalog = List.hd (sort_newest_first catalog.snapshots)
let last_good catalog = List.find catalog.snapshots ~f:(fun item -> item.last_good)
let string_list_json values = `List (List.map values ~f:(fun value -> `String value))

let summary_to_yojson summary =
  let validity_errors =
    match summary.validity with
    | Valid -> []
    | Invalid errors -> errors
  in
  `Assoc
    [ "id", `String (Id.to_string summary.id)
    ; "created_at", `String (Time_ns.to_string_utc summary.created_at)
    ; "display_time", `String (Id.display_time summary.id)
    ; "size_bytes", `Intlit (Int64.to_string summary.size_bytes)
    ; "latest", `Bool summary.latest
    ; "last_good", `Bool summary.last_good
    ; "validity", `String (validity_label summary.validity)
    ; "validity_errors", string_list_json validity_errors
    ; "warnings", string_list_json summary.warnings
    ; "sessions", `Int summary.session_count
    ; "windows", `Int summary.window_count
    ; "panes", `Int summary.pane_count
    ; "manifest", `Bool summary.manifest
    ; "legacy", `Bool summary.legacy
    ]
;;

let catalog_to_yojson catalog =
  `Assoc
    [ "directory", `String catalog.directory
    ; "directory_exists", `Bool catalog.directory_exists
    ; "total", `Int (List.length catalog.snapshots)
    ; "valid", `Int (valid_count catalog)
    ; "storage_bytes", `Intlit (Int64.to_string (storage_bytes catalog))
    ; ( "last_good"
      , Option.value_map (last_good catalog) ~default:`Null ~f:(fun item ->
          `String (Id.to_string item.id)) )
    ; "snapshots", `List (List.map catalog.snapshots ~f:summary_to_yojson)
    ; "warnings", string_list_json catalog.warnings
    ]
;;
