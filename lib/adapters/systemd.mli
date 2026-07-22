open! Core
open Async
module Service = Tmux_recovery_domain.Service

type definition =
  { name : string
  ; path : string
  ; contents : string
  }

type inventory =
  { definitions : definition list
  ; active : string list
  ; enabled : string list
  ; legacy_scripts : string list
  }

type config =
  { unit_directory : string
  ; bin_directory : string
  }

val default_config : unit -> config
val status : config -> Service.t Or_error.t Deferred.t
val status_from_inventory : inventory -> Service.t

val managed_definitions
  :  config
  -> binary_path:string
  -> tmux_path:string
  -> definition list
