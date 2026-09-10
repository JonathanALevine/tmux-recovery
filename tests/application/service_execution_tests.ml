open! Core
open Async
module App = Tmux_recovery_application.Service
module Service = Tmux_recovery_domain.Service

let rec remove_tree path =
  if Poly.equal (Sys_unix.is_directory path) `Yes
  then (
    Sys_unix.ls_dir path
    |> List.iter ~f:(fun name -> remove_tree (Filename.concat path name));
    Core_unix.rmdir path)
  else if Poly.equal (Sys_unix.file_exists path) `Yes
  then Core_unix.unlink path
;;

let with_fixture f =
  let root = Core_unix.mkdtemp "/tmp/tmux-recovery-service-test-XXXXXX" in
  Exn.protect
    ~finally:(fun () -> remove_tree root)
    ~f:(fun () ->
      let app =
        App.create
          ~platform:(Other "fixture")
          ~data_directory:(Filename.concat root "data")
          ~state_directory:(Filename.concat root "state")
          ()
      in
      (* Commands in this plan only create fixture markers. No real service manager or
         installed service directory is accessed. *)
      let marker name : Service.command =
        { program = "/bin/sh"
        ; arguments = [ "-c"; ": > \"$1\""; "fixture"; Filename.concat root name ]
        }
      in
      let file : Service.managed_file =
        { path = Filename.concat root "units/test.service"
        ; contents = "ExecStart=/fixture/tmux-recovery restore --if-empty --quiet\n"
        }
      in
      let plan : Service.plan =
        { manager = Unsupported "fixture"
        ; stable_binary = "/bin/sh"
        ; files = [ file ]
        ; enable_commands = [ marker "enabled" ]
        ; disable_commands = [ marker "disabled" ]
        ; conflicts = []
        }
      in
      f root app plan file)
;;

let run f = Thread_safe.block_on_async_exn f
let exists path = Poly.equal (Sys_unix.file_exists path) `Yes

let%test_unit "service enable and disable execute directly against the supplied plan" =
  with_fixture (fun root app plan file ->
    run (fun () -> App.enable app plan) |> Or_error.ok_exn;
    [%test_eq: string] (In_channel.read_all file.path) file.contents;
    assert (exists (Filename.concat root "enabled"));
    run (fun () -> App.disable app plan) |> Or_error.ok_exn;
    assert (exists (Filename.concat root "disabled"));
    assert (exists file.path))
;;

let%test_unit "conflicting services and missing runtimes fail before writes or commands" =
  with_fixture (fun root app plan file ->
    let conflicting = { plan with conflicts = [ "legacy timer" ] } in
    assert (Result.is_error (run (fun () -> App.enable app conflicting)));
    let missing = { plan with stable_binary = Filename.concat root "missing" } in
    assert (Result.is_error (run (fun () -> App.enable app missing)));
    assert (not (exists file.path));
    assert (not (exists (Filename.concat root "enabled"))))
;;

let%test_unit "a failed service enable restores the previous definitions" =
  with_fixture (fun root app plan file ->
    Core_unix.mkdir_p (Filename.dirname file.path);
    Out_channel.write_all file.path ~data:"previous definition\n";
    let plan =
      { plan with
        enable_commands = [ { program = "/bin/sh"; arguments = [ "-c"; "exit 1" ] } ]
      }
    in
    assert (Result.is_error (run (fun () -> App.enable app plan)));
    [%test_eq: string] (In_channel.read_all file.path) "previous definition\n";
    assert (exists (Filename.concat root "disabled")))
;;
