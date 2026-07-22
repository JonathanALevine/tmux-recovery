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

let asset_kind_label = function
  | Script -> "script"
  | Definition -> "service definition"
;;

let to_yojson plan =
  let asset item =
    `Assoc
      [ "path", `String item.path
      ; "kind", `String (asset_kind_label item.kind)
      ; "exists", `Bool item.exists
      ; ( "sha256"
        , Option.value_map item.sha256 ~default:`Null ~f:(fun value -> `String value) )
      ; "loaded", `Bool item.loaded
      ]
  and command (item : Service.command) =
    `Assoc
      [ "program", `String item.program
      ; "arguments", `List (List.map item.arguments ~f:(fun value -> `String value))
      ]
  in
  `Assoc
    [ "manager", `String (Service.manager_label plan.manager)
    ; "backup_directory", `String plan.backup_directory
    ; "assets", `List (List.map plan.assets ~f:asset)
    ; "disable_commands", `List (List.map plan.disable_commands ~f:command)
    ; "managed_services", Service.plan_to_yojson plan.managed_services
    ]
;;
