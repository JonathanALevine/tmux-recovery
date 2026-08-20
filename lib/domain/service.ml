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
  ; autonomy : component
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

let manager_label = function
  | Launchd -> "launchd"
  | Systemd -> "systemd --user"
  | Unsupported platform -> "unsupported (" ^ platform ^ ")"
;;

let ownership_label = function
  | Absent -> "absent"
  | Legacy -> "legacy/unmanaged"
  | Managed -> "tmux-recovery-managed"
  | Drifted -> "drifted"
;;

let activation_label = function
  | Not_installed -> "not installed"
  | Installed -> "installed, not loaded"
  | Loaded -> "loaded"
  | Disabled -> "disabled"
  | Unknown -> "unknown"
;;

let empty_component =
  { activation = Not_installed; schedule = None; definition = None; command = None }
;;

let estimate_next_run ~now ~last_run ~interval_seconds =
  if interval_seconds <= 0
  then None
  else (
    let elapsed_seconds = Time_ns.diff now last_run |> Time_ns.Span.to_sec in
    let intervals =
      if Float.(elapsed_seconds < 0.)
      then 1
      else Float.iround_down_exn (elapsed_seconds /. Float.of_int interval_seconds) + 1
    in
    Time_ns.Span.of_int_sec (intervals * interval_seconds)
    |> Time_ns.add last_run
    |> Option.some)
;;

let string_option_json = function
  | None -> `Null
  | Some value -> `String value
;;

let string_list_json values = `List (List.map values ~f:(fun value -> `String value))

let component_to_yojson component =
  `Assoc
    [ "activation", `String (activation_label component.activation)
    ; "schedule", string_option_json component.schedule
    ; "definition", string_option_json component.definition
    ; "command", string_option_json component.command
    ]
;;

let to_yojson (status : t) =
  `Assoc
    [ "manager", `String (manager_label status.manager)
    ; "ownership", `String (ownership_label status.ownership)
    ; "periodic_save", component_to_yojson status.periodic_save
    ; "autonomy", component_to_yojson status.autonomy
    ; "login_restore", component_to_yojson status.login_restore
    ; "binary_path", string_option_json status.binary_path
    ; "binary_version", string_option_json status.binary_version
    ; "last_result", string_option_json status.last_result
    ; "next_run", string_option_json status.next_run
    ; "last_restore", string_option_json status.last_restore
    ; "conflicts", string_list_json status.conflicts
    ; "warnings", string_list_json status.warnings
    ]
;;

let plan_to_yojson (plan : plan) =
  let file (item : managed_file) =
    `Assoc [ "path", `String item.path; "contents", `String item.contents ]
  and command (item : command) =
    `Assoc
      [ "program", `String item.program
      ; "arguments", `List (List.map item.arguments ~f:(fun value -> `String value))
      ]
  in
  `Assoc
    [ "manager", `String (manager_label plan.manager)
    ; "stable_binary", `String plan.stable_binary
    ; "files", `List (List.map plan.files ~f:file)
    ; "enable_commands", `List (List.map plan.enable_commands ~f:command)
    ; "disable_commands", `List (List.map plan.disable_commands ~f:command)
    ; "conflicts", string_list_json plan.conflicts
    ]
;;

let sync_plan_to_yojson plan =
  `Assoc
    [ "source", `String plan.source
    ; "destination", `String plan.destination
    ; "current", `String plan.current
    ; "previous", `String plan.previous
    ; "version", `String plan.version
    ; "sha256", `String plan.sha256
    ]
;;
