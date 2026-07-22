open! Core
open Async
module Service = Tmux_recovery_domain.Service

type config = { directory : string }

let version_is_safe version =
  (not (String.is_empty version))
  && String.for_all version ~f:(function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '-' | '+' -> true
    | _ -> false)
;;

let digest_file path = In_channel.read_all path |> Sha256.digest_string

let plan_sync config ~source ~version =
  if not (version_is_safe version)
  then Or_error.error_s [%message "version is not safe as a directory name" version]
  else if not (Poly.equal (Sys_unix.file_exists source) `Yes)
  then Or_error.error_s [%message "runtime source does not exist" source]
  else if not (Result.is_ok (Core_unix.access source [ `Exec ]))
  then Or_error.error_s [%message "runtime source is not executable" source]
  else (
    let source = Filename_unix.realpath source in
    let bin_directory = Filename.concat config.directory "bin" in
    Ok
      { Service.source
      ; destination =
          Filename.concat (Filename.concat bin_directory version) "tmux-recovery"
      ; current = Filename.concat bin_directory "current"
      ; previous = Filename.concat bin_directory "previous"
      ; version
      ; sha256 = digest_file source
      })
;;

let plan config ~source ~version =
  In_thread.run (fun () ->
    Or_error.try_with_join (fun () -> plan_sync config ~source ~version))
;;

let write_all fd contents =
  let rec loop position =
    if position < String.length contents
    then (
      let written =
        Core_unix.write_substring
          fd
          ~pos:position
          ~len:(String.length contents - position)
          ~buf:contents
      in
      if written = 0 then failwith "short runtime binary write";
      loop (position + written))
  in
  loop 0
;;

let atomic_symlink ~directory ~name ~target =
  let path = Filename.concat directory name in
  let temporary =
    Filename.concat directory [%string ".%{name}.tmp-%{Core_unix.getpid ()#Pid}"]
  in
  (match Sys_unix.file_exists temporary with
   | `Yes -> Core_unix.unlink temporary
   | `No | `Unknown -> ());
  Core_unix.symlink ~target ~link_name:temporary;
  Core_unix.rename ~src:temporary ~dst:path
;;

let apply_sync config (plan : Service.sync_plan) =
  let bin_directory = Filename.concat config.directory "bin" in
  let version_directory = Filename.dirname plan.destination in
  Core_unix.mkdir_p ~perm:0o700 version_directory;
  if not (Poly.equal (Sys_unix.file_exists plan.destination) `Yes)
  then (
    let temporary =
      Filename.concat
        version_directory
        [%string ".tmux-recovery.tmp-%{Core_unix.getpid ()#Pid}"]
    in
    Exn.protect
      ~f:(fun () ->
        let fd =
          Core_unix.openfile
            temporary
            ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
            ~perm:0o700
        in
        Exn.protect
          ~f:(fun () ->
            write_all fd (In_channel.read_all plan.source);
            Core_unix.fsync fd)
          ~finally:(fun () -> Core_unix.close fd);
        if not (String.equal plan.sha256 (digest_file temporary))
        then failwith "staged runtime hash differs from source";
        Core_unix.rename ~src:temporary ~dst:plan.destination)
      ~finally:(fun () ->
        match Sys_unix.file_exists temporary with
        | `Yes -> Core_unix.unlink temporary
        | `No | `Unknown -> ()));
  if not (String.equal plan.sha256 (digest_file plan.destination))
  then failwith "existing versioned runtime hash differs from requested source";
  (match Sys_unix.is_symlink plan.current with
   | `Yes ->
     let old_target = Core_unix.readlink plan.current in
     if not (String.equal old_target plan.version)
     then atomic_symlink ~directory:bin_directory ~name:"previous" ~target:old_target
   | `No | `Unknown -> ());
  atomic_symlink ~directory:bin_directory ~name:"current" ~target:plan.version;
  let fd = Core_unix.openfile bin_directory ~mode:[ O_RDONLY; O_CLOEXEC ] in
  Exn.protect ~f:(fun () -> Core_unix.fsync fd) ~finally:(fun () -> Core_unix.close fd)
;;

let apply config plan =
  In_thread.run (fun () -> Or_error.try_with (fun () -> apply_sync config plan))
;;

let rollback_sync config =
  let bin_directory = Filename.concat config.directory "bin" in
  let current = Filename.concat bin_directory "current"
  and previous = Filename.concat bin_directory "previous" in
  if (not (Poly.equal (Sys_unix.is_symlink current) `Yes))
     || not (Poly.equal (Sys_unix.is_symlink previous) `Yes)
  then failwith "runtime rollback requires both current and previous pointers";
  let current_target = Core_unix.readlink current
  and previous_target = Core_unix.readlink previous in
  let previous_binary =
    Filename.concat (Filename.concat bin_directory previous_target) "tmux-recovery"
  in
  if not (Poly.equal (Sys_unix.file_exists previous_binary) `Yes)
  then failwith "previous runtime binary is missing";
  atomic_symlink ~directory:bin_directory ~name:"current" ~target:previous_target;
  atomic_symlink ~directory:bin_directory ~name:"previous" ~target:current_target
;;

let rollback config =
  In_thread.run (fun () -> Or_error.try_with (fun () -> rollback_sync config))
;;
