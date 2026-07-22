open! Core
open Async
module App_recovery = Tmux_recovery_application.Recovery
module App_migrate = Tmux_recovery_application.Migrate
module App_service = Tmux_recovery_application.Service
module App_snapshot = Tmux_recovery_application.Snapshot
module Native_snapshot = Tmux_recovery_domain.Native_snapshot
module Migration = Tmux_recovery_domain.Migration
module Recovery = Tmux_recovery_domain.Recovery
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Workspace = Tmux_recovery_domain.Workspace

let schema_version = "1"
let version = "0.3.0-dev.6"

let envelope ~command ?(warnings = []) data =
  `Assoc
    [ "schema_version", `String schema_version
    ; "command", `String command
    ; "ok", `Bool true
    ; "data", data
    ; "warnings", `List (List.map warnings ~f:(fun warning -> `String warning))
    ; "error", `Null
    ]
;;

let print_json json = Yojson.Safe.pretty_to_string json |> print_endline

let socket_param =
  Command.Param.flag
    "--socket"
    (Command.Param.optional Command.Param.string)
    ~doc:"NAME inspect a named tmux socket (the value passed to tmux -L)"
;;

let json_param =
  Command.Param.flag "--json" Command.Param.no_arg ~doc:" emit stable versioned JSON"
;;

let service socket_name = App_recovery.create ?socket_name ()

let snapshot_directory_param =
  Command.Param.flag
    "--directory"
    (Command.Param.optional Command.Param.string)
    ~doc:"PATH inspect a specific tmux-resurrect directory"
;;

let native_snapshot_directory_param =
  Command.Param.flag
    "--native-directory"
    (Command.Param.optional Command.Param.string)
    ~doc:"PATH use a specific native tmux-recovery snapshot directory"
;;

let status_command =
  Command.async_or_error
    ~summary:"Show live tmux and recovery readiness"
    (let%map_open.Command socket_name = socket_param
     and json = json_param in
     fun () ->
       let recovery = service socket_name in
       let%map workspace = App_recovery.workspace recovery
       and plan = App_recovery.plan recovery in
       let%map.Or_error workspace, plan = Or_error.both workspace plan in
       if json
       then
         envelope
           ~command:"status"
           ~warnings:plan.warnings
           (`Assoc
             [ "version", `String version
             ; "workspace", Workspace.to_yojson workspace
             ; "recovery", Recovery.to_yojson plan
             ])
         |> print_json
       else (
         let server = if workspace.server.available then "running" else "not running" in
         let tmux_version = Option.value workspace.server.version ~default:"unknown" in
         let session_count = Map.length workspace.sessions in
         let window_count = Map.length workspace.windows in
         let pane_count = Map.length workspace.panes in
         printf "tmux-recovery %s\n" version;
         printf "tmux server:   %s (%s)\n" server tmux_version;
         printf
           "workspace:     %d sessions, %d windows, %d panes\n"
           session_count
           window_count
           pane_count;
         if workspace.server.available
         then (
           printf "recovery plan: ";
           Recovery.counts plan
           |> List.map ~f:(fun (action, count) ->
             [%string "%{Recovery.Action.label action}=%{count#Int}"])
           |> String.concat ~sep:", "
           |> print_endline)
         else print_endline "next action:    start tmux, then run tmux-recovery status"))
;;

let tree_lines workspace =
  let line prefix marker label = prefix ^ marker ^ label in
  Workspace.ordered_sessions workspace
  |> List.concat_map ~f:(fun session ->
    let session_marker = if session.attached then "● " else "○ " in
    let session_line = line "" session_marker session.name in
    let links = Workspace.links_for_session workspace ~session_id:session.id in
    let window_lines =
      links
      |> List.concat_mapi ~f:(fun link_index link ->
        let window = Map.find_exn workspace.windows link.window_id in
        let last_link = link_index = List.length links - 1 in
        let elbow = if last_link then "└─" else "├─" in
        let continuation = if last_link then "  " else "│ " in
        let active = if link.active then "*" else " " in
        let shared =
          if Workspace.linked_session_count workspace ~window_id:window.id > 1
          then " [shared]"
          else ""
        in
        let window_line =
          [%string "  %{elbow} %{link.index#Int}:%{window.name}%{active}%{shared}"]
        in
        let panes = Workspace.panes_for_window workspace ~window_id:window.id in
        let pane_lines =
          panes
          |> List.mapi ~f:(fun pane_index pane ->
            let pane_elbow = if pane_index = List.length panes - 1 then "└─" else "├─" in
            let decision = Recovery.classify pane in
            [%string
              "  %{continuation} %{pane_elbow} pane %{pane.index#Int} · \
               %{pane.current_command} [%{Recovery.Action.label decision.action}]"])
        in
        window_line :: pane_lines)
    in
    session_line :: window_lines)
;;

let tree_command =
  Command.async_or_error
    ~summary:"Print the normalized live workspace as a tree"
    (let%map_open.Command socket_name = socket_param
     and json = json_param in
     fun () ->
       let%map workspace = App_recovery.workspace (service socket_name) in
       let%map.Or_error workspace in
       if json
       then envelope ~command:"tree" (Workspace.to_yojson workspace) |> print_json
       else if workspace.server.available
       then tree_lines workspace |> List.iter ~f:print_endline
       else print_endline "No tmux server is running.")
;;

let plan_command =
  Command.async_or_error
    ~summary:"Preview conservative application recovery decisions"
    (let%map_open.Command socket_name = socket_param
     and json = json_param in
     fun () ->
       let%map plan = App_recovery.plan (service socket_name) in
       let%map.Or_error plan in
       if json
       then
         envelope
           ~command:"processes plan"
           ~warnings:plan.warnings
           (Recovery.to_yojson plan)
         |> print_json
       else (
         printf "%-8s  %-18s  %-14s  %s\n" "PANE" "OBSERVED" "ACTION" "FIDELITY";
         List.iter plan.decisions ~f:(fun decision ->
           printf
             "%-8s  %-18s  %-14s  %s\n"
             decision.pane_id
             decision.observed
             (Recovery.Action.label decision.action)
             decision.fidelity);
         List.iter plan.warnings ~f:(printf "warning: %s\n")))
;;

let processes_command =
  Command.group
    ~summary:"Inspect pane application recovery policy"
    [ "plan", plan_command ]
;;

let print_snapshot_summary (summary : Snapshot.summary) =
  let marker = if summary.latest then "*" else " " in
  let badges =
    [ Option.some_if summary.latest "latest"
    ; Option.some_if summary.last_good "last-good"
    ; Option.some_if summary.legacy "legacy"
    ; Option.some_if summary.manifest "manifest"
    ; (match summary.validity with
       | Valid -> None
       | Invalid _ -> Some "invalid")
    ]
    |> List.filter_opt
    |> String.concat ~sep:","
  in
  printf
    "%s %-19s  %-7s  %3d %3d %3d  %8Ld  %-28s %s\n"
    marker
    (Snapshot.Id.display_time summary.id)
    (Snapshot.validity_label summary.validity)
    summary.session_count
    summary.window_count
    summary.pane_count
    summary.size_bytes
    (Snapshot.Id.to_string summary.id)
    badges
;;

let snapshots_list_command =
  Command.async_or_error
    ~summary:"List native and compatible tmux-resurrect snapshots"
    (let%map_open.Command directory = snapshot_directory_param
     and native_directory = native_snapshot_directory_param
     and json = json_param in
     fun () ->
       let%map catalog =
         App_snapshot.list (App_snapshot.create ?directory ?native_directory ())
       in
       let%map.Or_error catalog in
       if json
       then
         envelope
           ~command:"snapshots list"
           ~warnings:catalog.warnings
           (Snapshot.catalog_to_yojson catalog)
         |> print_json
       else (
         printf "Snapshot directory: %s\n" catalog.directory;
         if List.is_empty catalog.snapshots
         then print_endline "No tmux-resurrect snapshots found."
         else (
           printf
             "  %-19s  %-7s  %3s %3s %3s  %8s  %-28s %s\n"
             "CREATED"
             "VALID"
             "SES"
             "WIN"
             "PAN"
             "BYTES"
             "ID"
             "BADGES";
           List.iter catalog.snapshots ~f:print_snapshot_summary);
         List.iter catalog.warnings ~f:(printf "warning: %s\n")))
;;

let snapshots_show_command =
  Command.async_or_error
    ~summary:"Show one native or compatible tmux-resurrect snapshot"
    (let%map_open.Command id = anon ("ID" %: string)
     and directory = snapshot_directory_param
     and native_directory = native_snapshot_directory_param
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind id = Snapshot.Id.of_string id |> Deferred.return in
       let%bind summary =
         App_snapshot.show (App_snapshot.create ?directory ?native_directory ()) id
       in
       if json
       then
         envelope ~command:"snapshots show" (Snapshot.summary_to_yojson summary)
         |> print_json
       else (
         printf "Snapshot:      %s\n" (Snapshot.Id.to_string summary.id);
         printf "Created:       %s\n" (Snapshot.Id.display_time summary.id);
         printf "Validity:      %s\n" (Snapshot.validity_label summary.validity);
         printf "Latest:        %b\n" summary.latest;
         printf "Last good:     %b\n" summary.last_good;
         printf "Sessions:      %d\n" summary.session_count;
         printf "Windows:       %d\n" summary.window_count;
         printf "Panes:         %d\n" summary.pane_count;
         printf "Bytes:         %Ld\n" summary.size_bytes;
         printf "Manifest:      %s\n" (if summary.manifest then "present" else "absent");
         printf
           "Compatibility: %s\n"
           (if summary.legacy then "legacy/upstream" else "managed");
         (match summary.validity with
          | Valid -> ()
          | Invalid errors -> List.iter errors ~f:(printf "invalid: %s\n"));
         List.iter summary.warnings ~f:(printf "warning: %s\n"));
       return ())
;;

let snapshots_save_command =
  Command.async_or_error
    ~summary:"Create a guarded native tmux-recovery snapshot"
    (let%map_open.Command socket_name = socket_param
     and native_directory = native_snapshot_directory_param
     and trigger =
       flag
         "--trigger"
         (optional_with_default "manual" string)
         ~doc:"REASON manual, timer, or shutdown"
     and dry_run =
       flag "--dry-run" no_arg ~doc:" show the exact save plan without writing"
     and quiet = flag "--quiet" no_arg ~doc:" suppress successful human-readable output"
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind trigger = Native_snapshot.Trigger.of_string trigger |> Deferred.return in
       let snapshots =
         App_snapshot.create ?native_directory ?socket_name ~tool_version:version ()
       in
       if dry_run
       then (
         let%map preparation = App_snapshot.prepare_save snapshots ~trigger in
         match preparation with
         | Noop reason ->
           if json
           then
             envelope
               ~command:"snapshots save"
               (`Assoc
                 [ "dry_run", `Bool true; "noop", `Bool true; "reason", `String reason ])
             |> print_json
           else printf "No snapshot would be written: %s.\n" reason
         | Ready (_, plan) ->
           if json
           then
             envelope
               ~command:"snapshots save"
               (`Assoc
                 [ "dry_run", `Bool true
                 ; "noop", `Bool false
                 ; "plan", Native_snapshot.save_plan_to_yojson plan
                 ])
             |> print_json
           else (
             printf "Native snapshot save plan\n";
             printf "ID:          %s\n" (Snapshot.Id.to_string plan.id);
             printf "Directory:   %s\n" plan.directory;
             printf "Trigger:     %s\n" (Native_snapshot.Trigger.to_string plan.trigger);
             printf
               "Workspace:   %d sessions, %d windows, %d panes\n"
               plan.session_count
               plan.window_count
               plan.pane_count))
       else (
         let%map result = App_snapshot.save snapshots ~trigger in
         match result with
         | Save_noop reason ->
           if json
           then
             envelope
               ~command:"snapshots save"
               (`Assoc
                 [ "saved", `Bool false; "noop", `Bool true; "reason", `String reason ])
             |> print_json
           else if not quiet
           then printf "No snapshot written: %s.\n" reason
         | Saved summary ->
           if json
           then
             envelope
               ~command:"snapshots save"
               (`Assoc
                 [ "saved", `Bool true; "snapshot", Snapshot.summary_to_yojson summary ])
             |> print_json
           else if not quiet
           then (
             printf "Saved %s\n" (Snapshot.Id.to_string summary.id);
             printf
               "Workspace: %d sessions, %d windows, %d panes\n"
               summary.session_count
               summary.window_count
               summary.pane_count)))
;;

let snapshots_restore_command =
  Command.async_or_error
    ~summary:"Plan or perform a guarded native snapshot restore"
    (let%map_open.Command selector = anon ("SNAPSHOT|latest|last-good" %: string)
     and socket_name = socket_param
     and native_directory = native_snapshot_directory_param
     and dry_run =
       flag "--dry-run" no_arg ~doc:" show the restore plan without changing tmux"
     and approve =
       flag "--approve" no_arg ~doc:" approve mutation of an empty target socket"
     and no_applications =
       flag
         "--no-applications"
         no_arg
         ~doc:" restore structure and shells without approved application restarts"
     and if_empty =
       flag
         "--if-empty"
         no_arg
         ~doc:" succeed without restoring when the target already has sessions"
     and quiet = flag "--quiet" no_arg ~doc:" suppress successful human-readable output"
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let snapshots =
         App_snapshot.create ?native_directory ?socket_name ~tool_version:version ()
       in
       let%bind target_has_sessions =
         if if_empty && not dry_run
         then (
           let%map workspace = App_recovery.workspace (service socket_name) in
           not (Map.is_empty workspace.sessions))
         else return false
       in
       if target_has_sessions
       then (
         if json
         then
           envelope
             ~command:"snapshots restore"
             (`Assoc
               [ "restored", `Bool false
               ; "noop", `Bool true
               ; "reason", `String "target already contains sessions"
               ])
           |> print_json
         else if not quiet
         then print_endline "No restore needed: target already contains sessions.";
         return ())
       else (
         let%bind id = App_snapshot.resolve_native snapshots selector in
         if dry_run
         then (
           let%map plan = App_snapshot.prepare_restore snapshots id in
           if json
           then
             envelope
               ~command:"snapshots restore"
               (`Assoc
                 [ "dry_run", `Bool true
                 ; "plan", Native_snapshot.restore_plan_to_yojson plan
                 ])
             |> print_json
           else if not quiet
           then (
             let workspace = plan.snapshot.workspace in
             printf "Native snapshot restore plan\n";
             printf "Snapshot:    %s\n" (Snapshot.Id.to_string plan.snapshot.id);
             printf
               "Target:      %s\n"
               (Option.value plan.socket_name ~default:"default tmux socket");
             printf
               "Workspace:   %d sessions, %d windows, %d panes\n"
               (Map.length workspace.sessions)
               (Map.length workspace.windows)
               (Map.length workspace.panes);
             Recovery.counts plan.recovery
             |> List.iter ~f:(fun (action, count) ->
               printf "%-12s %d\n" (Recovery.Action.label action) count);
             List.iter plan.recovery.warnings ~f:(printf "warning: %s\n")))
         else if not approve
         then
           Deferred.Or_error.error_string
             "restore changes tmux state; review --dry-run and rerun with --approve"
         else (
           let%map result =
             App_snapshot.restore snapshots id ~launch_applications:(not no_applications)
           in
           if json
           then
             envelope
               ~command:"snapshots restore"
               ~warnings:result.application_warnings
               (`Assoc
                 [ "snapshot", `String (Snapshot.Id.to_string result.snapshot_id)
                 ; "sessions", `Int result.session_count
                 ; "windows", `Int result.window_count
                 ; "panes", `Int result.pane_count
                 ; "applications", `Bool (not no_applications)
                 ])
             |> print_json
           else if not quiet
           then (
             printf "Restored %s\n" (Snapshot.Id.to_string result.snapshot_id);
             printf
               "Workspace: %d sessions, %d windows, %d panes\n"
               result.session_count
               result.window_count
               result.pane_count;
             List.iter result.application_warnings ~f:(printf "warning: %s\n")))))
;;

let snapshots_validate_command =
  Command.async_or_error
    ~summary:"Validate a native snapshot bundle and its integrity hash"
    (let%map_open.Command selector = anon ("SNAPSHOT|latest|last-good" %: string)
     and native_directory = native_snapshot_directory_param
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let snapshots = App_snapshot.create ?native_directory () in
       let%bind id = App_snapshot.resolve_native snapshots selector in
       let%map snapshot = App_snapshot.load_native snapshots id in
       if json
       then
         envelope
           ~command:"snapshots validate"
           (`Assoc
             [ "valid", `Bool true; "snapshot", Native_snapshot.to_yojson snapshot ])
         |> print_json
       else (
         printf "Valid native snapshot: %s\n" (Snapshot.Id.to_string snapshot.id);
         printf
           "Workspace: %d sessions, %d windows, %d panes\n"
           (Map.length snapshot.workspace.sessions)
           (Map.length snapshot.workspace.windows)
           (Map.length snapshot.workspace.panes)))
;;

let snapshots_prune_command =
  Command.async_or_error
    ~summary:"Preview or apply conservative native snapshot retention"
    (let%map_open.Command native_directory = native_snapshot_directory_param
     and apply = flag "--apply" no_arg ~doc:" delete the reviewed retention candidates"
     and dry_run = flag "--dry-run" no_arg ~doc:" preview retention (the default)"
     and json = json_param in
     fun () ->
       if apply && dry_run
       then Deferred.Or_error.error_string "choose either --dry-run or --apply"
       else (
         let%map candidates =
           App_snapshot.prune (App_snapshot.create ?native_directory ()) ~apply
         in
         let%map.Or_error candidates in
         if json
         then
           envelope
             ~command:"snapshots prune"
             (`Assoc
               [ "applied", `Bool apply
               ; "snapshots", `List (List.map candidates ~f:Snapshot.summary_to_yojson)
               ])
           |> print_json
         else if List.is_empty candidates
         then print_endline "No native snapshots are eligible for pruning."
         else (
           printf
             "%s %d native snapshot%s:\n"
             (if apply then "Pruned" else "Would prune")
             (List.length candidates)
             (if List.length candidates = 1 then "" else "s");
           List.iter candidates ~f:(fun summary ->
             printf "  %s\n" (Snapshot.Id.to_string summary.id)))))
;;

let snapshots_import_command =
  Command.async_or_error
    ~summary:"Convert a compatible tmux-resurrect file into a native bundle"
    (let%map_open.Command legacy_id = anon ("LEGACY_ID" %: string)
     and directory = snapshot_directory_param
     and native_directory = native_snapshot_directory_param
     and dry_run = flag "--dry-run" no_arg ~doc:" validate and show the import plan"
     and approve = flag "--approve" no_arg ~doc:" approve writing the native bundle"
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       if Bool.equal dry_run approve
       then Deferred.Or_error.error_string "choose exactly one of --dry-run or --approve"
       else (
         let%bind legacy_id = Snapshot.Id.of_string legacy_id |> Deferred.return in
         let snapshots =
           App_snapshot.create ?directory ?native_directory ~tool_version:version ()
         in
         if dry_run
         then (
           let%map _, plan = App_snapshot.prepare_import_resurrect snapshots legacy_id in
           if json
           then
             envelope
               ~command:"snapshots import-resurrect"
               (`Assoc
                 [ "dry_run", `Bool true
                 ; "legacy", `String (Snapshot.Id.to_string legacy_id)
                 ; "plan", Native_snapshot.save_plan_to_yojson plan
                 ])
             |> print_json
           else (
             printf "Would import %s\n" (Snapshot.Id.to_string legacy_id);
             printf "Native ID: %s\n" (Snapshot.Id.to_string plan.id);
             printf
               "Workspace: %d sessions, %d windows, %d panes\n"
               plan.session_count
               plan.window_count
               plan.pane_count))
         else (
           let%map summary = App_snapshot.import_resurrect snapshots legacy_id in
           if json
           then
             envelope
               ~command:"snapshots import-resurrect"
               (Snapshot.summary_to_yojson summary)
             |> print_json
           else (
             printf
               "Imported %s as %s\n"
               (Snapshot.Id.to_string legacy_id)
               (Snapshot.Id.to_string summary.id);
             printf
               "Workspace: %d sessions, %d windows, %d panes\n"
               summary.session_count
               summary.window_count
               summary.pane_count))))
;;

let snapshots_command =
  Command.group
    ~summary:"Inspect saved tmux workspaces"
    [ "list", snapshots_list_command
    ; "show", snapshots_show_command
    ; "save", snapshots_save_command
    ; "restore", snapshots_restore_command
    ; "validate", snapshots_validate_command
    ; "prune", snapshots_prune_command
    ; "import-resurrect", snapshots_import_command
    ]
;;

let service_status_command =
  Command.async_or_error
    ~summary:"Inspect launchd or systemd tmux automation"
    (let%map_open.Command json = json_param in
     fun () ->
       let%map status = App_service.status (App_service.create ()) in
       let%map.Or_error status in
       if json
       then
         envelope
           ~command:"service status"
           ~warnings:status.warnings
           (Service.to_yojson status)
         |> print_json
       else (
         printf "Manager:         %s\n" (Service.manager_label status.manager);
         printf "Ownership:       %s\n" (Service.ownership_label status.ownership);
         printf
           "Periodic save:    %s"
           (Service.activation_label status.periodic_save.activation);
         Option.iter status.periodic_save.schedule ~f:(printf " · %s");
         print_newline ();
         printf
           "Login restore:    %s"
           (Service.activation_label status.login_restore.activation);
         Option.iter status.login_restore.schedule ~f:(printf " · %s");
         print_newline ();
         printf
           "Runtime binary:   %s\n"
           (Option.value status.binary_path ~default:"not detected");
         printf
           "Binary version:   %s\n"
           (Option.value status.binary_version ~default:"unknown");
         printf
           "Recent result:   %s\n"
           (Option.value status.last_result ~default:"unavailable");
         printf
           "Next run:        %s\n"
           (Option.value status.next_run ~default:"unavailable");
         List.iter status.conflicts ~f:(printf "conflict: %s\n");
         List.iter status.warnings ~f:(printf "warning: %s\n")))
;;

let service_plan_command =
  Command.async_or_error
    ~summary:"Render the managed service plan without changing the service manager"
    (let%map_open.Command json = json_param in
     fun () ->
       let%map plan = App_service.plan (App_service.create ()) in
       let%map.Or_error plan in
       if json
       then envelope ~command:"service plan" (Service.plan_to_yojson plan) |> print_json
       else (
         printf "Manager:       %s\n" (Service.manager_label plan.manager);
         printf "Stable binary: %s\n" plan.stable_binary;
         print_endline "Definitions:";
         List.iter plan.files ~f:(fun file -> printf "  %s\n" file.Service.path);
         print_endline "Enable commands:";
         List.iter plan.enable_commands ~f:(fun command ->
           printf "  %s %s\n" command.program (String.concat command.arguments ~sep:" "));
         if not (List.is_empty plan.conflicts)
         then (
           print_endline "Conflicts (enable will refuse these):";
           List.iter plan.conflicts ~f:(printf "  %s\n"))))
;;

let service_sync_command =
  Command.async_or_error
    ~summary:"Stage this executable as the stable background-service runtime"
    (let%map_open.Command source =
       flag
         "--source"
         (optional_with_default Sys.executable_name string)
         ~doc:"PATH executable to stage (defaults to the running executable)"
     and dry_run = flag "--dry-run" no_arg ~doc:" show paths and hash without writing"
     and approve = flag "--approve" no_arg ~doc:" approve stable runtime mutation"
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       if dry_run && approve
       then Deferred.Or_error.error_string "choose either --dry-run or --approve"
       else if (not dry_run) && not approve
       then
         Deferred.Or_error.error_string
           "review service sync --dry-run, then rerun with --approve"
       else (
         let services = App_service.create () in
         let%bind plan = App_service.sync_plan services ~source ~version in
         let%bind () = if approve then App_service.sync services plan else return () in
         if json
         then
           envelope
             ~command:"service sync"
             (`Assoc
               [ "applied", `Bool approve; "plan", Service.sync_plan_to_yojson plan ])
           |> print_json
         else (
           printf "%s stable runtime\n" (if approve then "Staged" else "Would stage");
           printf "Source:      %s\n" plan.source;
           printf "Destination: %s\n" plan.destination;
           printf "Current:     %s\n" plan.current;
           printf "SHA-256:     %s\n" plan.sha256);
         return ()))
;;

let service_rollback_command =
  Command.async_or_error
    ~summary:"Swap the stable service runtime back to its previous version"
    (let%map_open.Command approve =
       flag "--approve" no_arg ~doc:" approve stable runtime pointer rollback"
     in
     fun () ->
       if not approve
       then Deferred.Or_error.error_string "runtime rollback requires --approve"
       else (
         let%map result = App_service.rollback (App_service.create ()) in
         let%map.Or_error () = result in
         print_endline "Rolled the stable runtime back to the previous version."))
;;

let service_enable_command =
  Command.async_or_error
    ~summary:"Install and load managed native services after conflict checks"
    (let%map_open.Command dry_run =
       flag "--dry-run" no_arg ~doc:" show the enable plan without changing services"
     and approve =
       flag "--approve" no_arg ~doc:" approve service installation and loading"
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       if Bool.equal dry_run approve
       then Deferred.Or_error.error_string "choose exactly one of --dry-run or --approve"
       else (
         let services = App_service.create () in
         let%bind plan = App_service.plan services in
         let%bind () = if approve then App_service.enable services plan else return () in
         if json
         then
           envelope
             ~command:"service enable"
             (`Assoc [ "applied", `Bool approve; "plan", Service.plan_to_yojson plan ])
           |> print_json
         else (
           printf
             "%s managed %s services.\n"
             (if approve then "Enabled" else "Would enable")
             (Service.manager_label plan.manager);
           List.iter plan.files ~f:(fun file -> printf "  %s\n" file.Service.path);
           if not (List.is_empty plan.conflicts)
           then (
             print_endline "Blocked by legacy conflicts:";
             List.iter plan.conflicts ~f:(printf "  %s\n")));
         return ()))
;;

let service_disable_command =
  Command.async_or_error
    ~summary:"Unload managed native services without deleting snapshot data"
    (let%map_open.Command dry_run =
       flag "--dry-run" no_arg ~doc:" show service-manager disable commands"
     and approve = flag "--approve" no_arg ~doc:" approve unloading managed services" in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       if Bool.equal dry_run approve
       then Deferred.Or_error.error_string "choose exactly one of --dry-run or --approve"
       else (
         let services = App_service.create () in
         let%bind plan = App_service.plan services in
         let%bind () = if approve then App_service.disable services plan else return () in
         printf "%s service-manager commands:\n" (if approve then "Ran" else "Would run");
         List.iter plan.disable_commands ~f:(fun command ->
           printf "  %s %s\n" command.program (String.concat command.arguments ~sep:" "));
         return ()))
;;

let service_command =
  Command.group
    ~summary:"Inspect background scheduling"
    [ "status", service_status_command
    ; "plan", service_plan_command
    ; "sync", service_sync_command
    ; "rollback", service_rollback_command
    ; "enable", service_enable_command
    ; "disable", service_disable_command
    ]
;;

let print_migration_plan (plan : Migration.plan) =
  printf "Manager:          %s\n" (Service.manager_label plan.manager);
  printf "Rollback bundle:  %s\n" plan.backup_directory;
  print_endline "Legacy assets:";
  List.iter plan.assets ~f:(fun asset ->
    printf
      "  %-18s %-7s %s\n"
      (Migration.asset_kind_label asset.kind)
      (if asset.loaded then "loaded" else if asset.exists then "present" else "missing")
      asset.path);
  print_endline "Legacy disable commands:";
  List.iter plan.disable_commands ~f:(fun command ->
    printf "  %s %s\n" command.program (String.concat command.arguments ~sep:" "));
  printf "Managed definitions: %d\n" (List.length plan.managed_services.files)
;;

let migrate_plan_command =
  Command.async_or_error
    ~summary:"Inventory legacy assets and render a reversible migration plan"
    (let%map_open.Command json = json_param in
     fun () ->
       let%map plan = App_migrate.plan (App_migrate.create ()) in
       let%map.Or_error plan in
       if json
       then envelope ~command:"migrate plan" (Migration.to_yojson plan) |> print_json
       else print_migration_plan plan)
;;

let migrate_apply_command =
  Command.async_or_error
    ~summary:"Back up and replace loaded legacy automation with managed services"
    (let%map_open.Command approve =
       flag "--approve" no_arg ~doc:" approve the reviewed reversible cutover"
     in
     fun () ->
       if not approve
       then Deferred.Or_error.error_string "migration cutover requires --approve"
       else (
         let migrate = App_migrate.create () in
         let open Deferred.Or_error.Let_syntax in
         let%bind plan = App_migrate.plan migrate in
         let%map backup = App_migrate.apply migrate plan in
         printf "Native service cutover succeeded.\nRollback bundle: %s\n" backup))
;;

let migrate_rollback_command =
  Command.async_or_error
    ~summary:"Disable managed services and reload the backed-up legacy definitions"
    (let%map_open.Command approve =
       flag "--approve" no_arg ~doc:" approve rollback to legacy automation"
     in
     fun () ->
       if not approve
       then Deferred.Or_error.error_string "migration rollback requires --approve"
       else (
         let migrate = App_migrate.create () in
         let open Deferred.Or_error.Let_syntax in
         let%bind plan = App_migrate.plan migrate in
         let%map () = App_migrate.rollback migrate plan in
         print_endline "Managed services disabled and legacy automation reloaded."))
;;

let migrate_command =
  Command.group
    ~summary:"Plan, apply, or roll back legacy recovery migration"
    [ "status", migrate_plan_command
    ; "plan", migrate_plan_command
    ; "apply", migrate_apply_command
    ; "rollback", migrate_rollback_command
    ]
;;

let doctor_command =
  Command.async_or_error
    ~summary:"Check native recovery, tmux, snapshots, and service readiness"
    (let%map_open.Command socket_name = socket_param
     and json = json_param in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let recovery_service = service socket_name in
       let%bind workspace = App_recovery.workspace recovery_service in
       let%bind recovery_plan = App_recovery.plan recovery_service in
       let%bind snapshots = App_snapshot.list (App_snapshot.create ()) in
       let%bind services = App_service.status (App_service.create ()) in
       let native_last_good =
         List.find snapshots.snapshots ~f:(fun summary ->
           summary.last_good && (not summary.legacy) && Snapshot.is_valid summary)
       in
       let recovery_count action =
         List.Assoc.find
           (Recovery.counts recovery_plan)
           action
           ~equal:Recovery.Action.equal
         |> Option.value ~default:0
       in
       let codex_resumes = recovery_count Resume
       and blocked = recovery_count Blocked in
       let checks =
         [ ( "tmux executable"
           , `Pass
           , Option.value workspace.server.version ~default:"available" )
         ; ( "tmux server"
           , (if workspace.server.available then `Pass else `Warn)
           , if workspace.server.available
             then "running"
             else "not running; live tree is empty" )
         ; ( "workspace graph"
           , `Pass
           , [%string
               "%{Map.length workspace.sessions#Int} sessions / %{Map.length \
                workspace.windows#Int} canonical windows / %{Map.length \
                workspace.panes#Int} panes"] )
         ; ( "native last-good"
           , (if Option.is_some native_last_good then `Pass else `Warn)
           , Option.value_map
               native_last_good
               ~default:"no valid native last-good snapshot"
               ~f:(fun summary -> Snapshot.Id.to_string summary.id) )
         ; ( "application recovery"
           , (if blocked = 0 then `Pass else `Warn)
           , [%string
               "%{codex_resumes#Int} exact Codex resume(s) · %{blocked#Int} blocked \
                pane(s)"] )
         ; ( "managed services"
           , (if Service.equal_ownership services.ownership Managed then `Pass else `Warn)
           , [%string
               "%{Service.ownership_label services.ownership} · runtime %{Option.value \
                services.binary_version ~default:\"unknown\"}"] )
         ; ( "active conflicts"
           , (if List.is_empty services.conflicts then `Pass else `Warn)
           , if List.is_empty services.conflicts
             then "none"
             else [%string "%{List.length services.conflicts#Int} conflict(s)"] )
         ; ( "mutation safety"
           , `Pass
           , "guarded save/restore and service mutations require explicit approval" )
         ]
       in
       if json
       then (
         let data =
           checks
           |> List.map ~f:(fun (name, status, detail) ->
             `Assoc
               [ "name", `String name
               ; ( "status"
                 , `String
                     (match status with
                      | `Pass -> "pass"
                      | `Warn -> "warn") )
               ; "detail", `String detail
               ])
           |> fun checks -> `Assoc [ "checks", `List checks ]
         in
         envelope ~command:"doctor" data |> print_json)
       else
         List.iter checks ~f:(fun (name, status, detail) ->
           let mark =
             match status with
             | `Pass -> "PASS"
             | `Warn -> "WARN"
           in
           printf "%-4s  %-18s %s\n" mark name detail);
       return ())
;;

let commands =
  [ "status", status_command
  ; "tree", tree_command
  ; "processes", processes_command
  ; "snapshots", snapshots_command
  ; "service", service_command
  ; "migrate", migrate_command
  ; "doctor", doctor_command
  ]
;;
