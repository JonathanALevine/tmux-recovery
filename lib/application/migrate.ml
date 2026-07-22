open! Core
open Async
module Domain = Tmux_recovery_domain.Migration
module Service_domain = Tmux_recovery_domain.Service

type t =
  { services : Service.t
  ; adapter : Migration.config
  ; now : unit -> Time_ns.t
  ; nonce : unit -> string
  }

let nonce () =
  let state = Random.State.make_self_init () in
  Random.State.bits state land 0x3fffffff |> sprintf "%08x"
;;

let create () =
  { services = Service.create ()
  ; adapter = Migration.default_config ()
  ; now = Time_ns.now
  ; nonce
  }
;;

let plan t =
  let open Deferred.Or_error.Let_syntax in
  let%bind managed_services = Service.plan t.services in
  Migration.plan
    t.adapter
    ~manager:managed_services.manager
    ~managed_services
    ~now:(t.now ())
    ~nonce:(t.nonce ())
;;

let run_runtime binary arguments =
  Process.run ~prog:binary ~args:arguments () >>| Or_error.map ~f:ignore
;;

let rollback t plan =
  let%bind _ = Service.disable t.services plan.Domain.managed_services in
  let%bind commands = Migration.active_legacy_enable_commands t.adapter in
  match commands with
  | Error _ as error -> return error
  | Ok commands -> Migration.run_commands commands
;;

let apply t plan =
  let managed_services = { plan.Domain.managed_services with conflicts = [] } in
  let apply_steps () =
    let open Deferred.Or_error.Let_syntax in
    let%bind () = Migration.create_backup t.adapter plan in
    let%bind () = Migration.run_commands plan.disable_commands in
    let%bind () = Service.enable t.services managed_services in
    let%bind () =
      run_runtime
        managed_services.stable_binary
        [ "snapshots"; "save"; "--trigger"; "timer"; "--quiet" ]
    in
    let%bind () =
      run_runtime managed_services.stable_binary [ "snapshots"; "validate"; "last-good" ]
    in
    return plan.backup_directory
  in
  Deferred.bind (apply_steps ()) ~f:(function
    | Ok _ as success -> return success
    | Error original ->
      let%bind _rollback = rollback t plan in
      return (Error original))
;;
