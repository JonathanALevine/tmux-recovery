open! Core
open Async
module Service = Tmux_recovery_domain.Service
module Snapshot = Tmux_recovery_domain.Snapshot
module Native_domain = Tmux_recovery_domain.Native_snapshot
module Recovery = Tmux_recovery_domain.Recovery
module Workspace = Tmux_recovery_domain.Workspace

let row ~session_id ~session_name ~window_index =
  String.concat
    ~sep:"__TMUX_RECOVERY_FIELD_7F3A__"
    [ session_id
    ; session_name
    ; "1"
    ; "@7"
    ; Int.to_string window_index
    ; "shared-monitor"
    ; "1"
    ; "layout"
    ; "%9"
    ; "0"
    ; "1"
    ; "btop"
    ; "/tmp"
    ; "btop"
    ; "123"
    ; "/dev/ttys009"
    ]
;;

let%test_unit "tmux rows normalize linked windows and panes" =
  let workspace =
    Tmux_adapter.parse_rows
      ~socket_name:(Some "test")
      ~version:(Some "tmux 3.7")
      [ row ~session_id:"$1" ~session_name:"one" ~window_index:0
      ; row ~session_id:"$2" ~session_name:"two" ~window_index:3
      ]
    |> Or_error.ok_exn
  in
  [%test_eq: int] (Map.length workspace.sessions) 2;
  [%test_eq: int] (Map.length workspace.windows) 1;
  [%test_eq: int] (List.length workspace.window_links) 2;
  [%test_eq: int] (Map.length workspace.panes) 1
;;

let%test_unit "the bundled SHA-256 implementation matches standard vectors" =
  [%test_eq: string]
    (Sha256.digest_string "")
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  [%test_eq: string]
    (Sha256.digest_string "abc")
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
;;

let rec remove_tree path =
  match Sys_unix.is_symlink path with
  | `Yes -> Core_unix.unlink path
  | `No | `Unknown ->
    (match Sys_unix.is_directory path with
     | `Yes ->
       Sys_unix.ls_dir path
       |> List.iter ~f:(fun name -> remove_tree (Filename.concat path name));
       Core_unix.rmdir path
     | `No | `Unknown ->
       (match Sys_unix.file_exists path with
        | `Yes -> Core_unix.unlink path
        | `No | `Unknown -> ()))
;;

let sqlite_exec database sql = Sqlite3.exec database sql |> Sqlite3.Rc.check

let with_codex_databases f =
  let root = Core_unix.mkdtemp "/tmp/tmux-recovery-codex-XXXXXX" in
  Exn.protect
    ~finally:(fun () -> remove_tree root)
    ~f:(fun () ->
      let state = Sqlite3.db_open (Filename.concat root "state_5.sqlite") in
      sqlite_exec
        state
        "CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT NOT NULL, updated_at \
         INTEGER NOT NULL, updated_at_ms INTEGER, approval_mode TEXT NOT NULL, \
         sandbox_policy TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0)";
      sqlite_exec
        state
        "INSERT INTO threads VALUES ('019f8c7e-0000-7000-8000-000000000001', \
         '/tmp/project', 10, 10000, 'on-request', '{\"type\":\"workspace-write\"}', 0)";
      sqlite_exec
        state
        "INSERT INTO threads VALUES ('019f8c7e-0000-7000-8000-000000000002', \
         '/tmp/project', 20, 20000, 'never', '{\"type\":\"danger-full-access\"}', 0)";
      assert (Sqlite3.db_close state);
      let logs = Sqlite3.db_open (Filename.concat root "logs_2.sqlite") in
      sqlite_exec
        logs
        "CREATE TABLE logs (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, ts_nanos \
         INTEGER NOT NULL, thread_id TEXT, process_uuid TEXT)";
      sqlite_exec
        logs
        "INSERT INTO logs VALUES (1, 1, 1, '019f8c7e-0000-7000-8000-000000000001', \
         'pid:4242:test')";
      sqlite_exec
        logs
        "INSERT INTO logs VALUES (2, 2, 2, '019f8c7e-0000-7000-8000-999999999999', \
         'pid:4343:test')";
      assert (Sqlite3.db_close logs);
      let config =
        Codex.create
          ~codex_home:root
          ~executable_candidates:[ "/bin/false" ]
          ~process_executable:"ps"
      in
      f config)
;;

let%test_unit "Codex provider lookup prefers the exact process thread" =
  with_codex_databases (fun config ->
    let resume =
      Codex.lookup_for_processes config ~pids:[ 4242 ] ~fallback_cwd:"/tmp/project"
      |> Or_error.ok_exn
      |> Option.value_exn
    in
    [%test_eq: string] resume.thread_id "019f8c7e-0000-7000-8000-000000000001";
    assert (not resume.bypass_approvals))
;;

let%test_unit "an explicit Codex resume UUID is authoritative" =
  with_codex_databases (fun config ->
    let resume =
      Codex.lookup_for_processes
        config
        ~explicit_thread_id:"019f8c7e-0000-7000-8000-000000000001"
        ~pids:[ 9999 ]
        ~fallback_cwd:"/tmp/project"
      |> Or_error.ok_exn
      |> Option.value_exn
    in
    [%test_eq: string] resume.thread_id "019f8c7e-0000-7000-8000-000000000001";
    assert (not resume.bypass_approvals))
;;

let%test_unit "explicit Codex resume parsing accepts only a resume UUID argument" =
  [%test_eq: string option]
    (Codex.explicit_resume_thread_id
       "node /usr/local/bin/codex resume 019f8c7e-0000-7000-8000-000000000001 \
        --dangerously-bypass-approvals-and-sandbox")
    (Some "019f8c7e-0000-7000-8000-000000000001");
  [%test_eq: string option]
    (Codex.explicit_resume_thread_id
       "node /usr/local/bin/codex 019f8c7e-0000-7000-8000-000000000001")
    None
;;

let%test_unit "Codex cwd fallback uses the newest durable thread and restores policy" =
  with_codex_databases (fun config ->
    let resume =
      Codex.lookup_for_processes config ~pids:[ 9999 ] ~fallback_cwd:"/tmp/project"
      |> Or_error.ok_exn
      |> Option.value_exn
    in
    [%test_eq: string] resume.thread_id "019f8c7e-0000-7000-8000-000000000002";
    assert resume.bypass_approvals)
;;

let%test_unit "a stale process log falls back to a thread that still exists" =
  with_codex_databases (fun config ->
    let resume =
      Codex.lookup_for_processes config ~pids:[ 4343 ] ~fallback_cwd:"/tmp/project"
      |> Or_error.ok_exn
      |> Option.value_exn
    in
    [%test_eq: string] resume.thread_id "019f8c7e-0000-7000-8000-000000000002")
;;

let%test_unit "cwd fallback can be disabled when same-cwd Codex panes are ambiguous" =
  with_codex_databases (fun config ->
    let resume =
      Codex.lookup_for_processes
        config
        ~allow_cwd_fallback:false
        ~pids:[ 9999 ]
        ~fallback_cwd:"/tmp/project"
      |> Or_error.ok_exn
    in
    assert (Option.is_none resume))
;;

let%test_unit "a Codex-named window remains detected after its process exits" =
  with_codex_databases (fun config ->
    let session : Workspace.Session.t = { id = "$1"; name = "work"; attached = false }
    and window : Workspace.Window.t = { id = "@1"; name = "codex"; layout = "" }
    and link : Workspace.Window_link.t =
      { id = "$1/@1"; session_id = "$1"; window_id = "@1"; index = 0; active = true }
    and pane : Workspace.Pane.t =
      { id = "%1"
      ; window_id = "@1"
      ; index = 0
      ; active = true
      ; title = "shell"
      ; cwd = "/tmp/project"
      ; current_command = "zsh"
      ; pid = None
      ; tty = None
      }
    in
    let workspace =
      Workspace.create
        ~source:Live
        ~server:{ available = true; socket = Some "test"; version = Some "tmux test" }
        [ session ]
        [ window ]
        [ link ]
        [ pane ]
      |> Result.map_error ~f:(String.concat ~sep:"; ")
      |> Result.ok_or_failwith
    in
    let capture =
      Thread_safe.block_on_async_exn (fun () -> Codex.capture config workspace)
    in
    assert (Set.mem capture.detected_panes "%1");
    [%test_eq: int] (Map.length capture.resumes) 1)
;;

let native_fixture ~codex_unresolved ~id ~created_at =
  let session : Workspace.Session.t = { id = "$1"; name = "work"; attached = false }
  and window : Workspace.Window.t = { id = "@1"; name = "main"; layout = "" }
  and link : Workspace.Window_link.t =
    { id = "$1/@1"; session_id = "$1"; window_id = "@1"; index = 0; active = true }
  and pane : Workspace.Pane.t =
    { id = "%1"
    ; window_id = "@1"
    ; index = 0
    ; active = true
    ; title = "shell"
    ; cwd = "/tmp"
    ; current_command = "zsh"
    ; pid = None
    ; tty = None
    }
  in
  let workspace =
    Workspace.create
      ~source:Live
      ~server:{ available = true; socket = Some "test"; version = Some "tmux test" }
      [ session ]
      [ window ]
      [ link ]
      [ pane ]
    |> Result.map_error ~f:(String.concat ~sep:"; ")
    |> Result.ok_or_failwith
  in
  Native_domain.create
    ~codex_unresolved
    ~id
    ~created_at
    ~trigger:Manual
    ~tool_version:"test"
    workspace
  |> Or_error.ok_exn
;;

let%test_unit "native bundles commit atomically and reject hash corruption" =
  let root = Core_unix.mkdtemp "/tmp/tmux-recovery-store-XXXXXX" in
  Exn.protect
    ~finally:(fun () -> remove_tree root)
    ~f:(fun () ->
      let created_at = Time_ns.epoch in
      let id =
        Snapshot.Id.create_native ~created_at ~nonce:"0123abcd" |> Or_error.ok_exn
      in
      let config : Native_snapshot.config =
        { directory = Filename.concat root "snapshots"
        ; runtime_directory = Filename.concat root "run"
        ; maximum_snapshots = 10
        }
      in
      let snapshot = native_fixture ~codex_unresolved:String.Set.empty ~id ~created_at in
      let summary =
        Thread_safe.block_on_async_exn (fun () ->
          Native_snapshot.save config ~socket_name:(Some "test") snapshot)
        |> Or_error.ok_exn
      in
      assert summary.latest;
      assert summary.last_good;
      let id_string = Snapshot.Id.to_string id in
      [%test_eq: string]
        (Core_unix.readlink (Filename.concat config.directory "latest"))
        id_string;
      [%test_eq: int]
        ((Core_unix.stat (Filename.concat config.directory id_string)).st_perm land 0o777)
        0o700;
      let snapshot_file =
        Filename.concat (Filename.concat config.directory id_string) "snapshot.json"
      in
      Out_channel.write_all snapshot_file ~data:"{}";
      let loaded =
        Thread_safe.block_on_async_exn (fun () -> Native_snapshot.load config id)
      in
      assert (Result.is_error loaded))
;;

let%test_unit "an unresolved Codex snapshot cannot replace a valid last-good" =
  let root = Core_unix.mkdtemp "/tmp/tmux-recovery-store-XXXXXX" in
  Exn.protect
    ~finally:(fun () -> remove_tree root)
    ~f:(fun () ->
      let config : Native_snapshot.config =
        { directory = Filename.concat root "snapshots"
        ; runtime_directory = Filename.concat root "run"
        ; maximum_snapshots = 10
        }
      in
      let save nonce seconds unresolved =
        let created_at = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds) in
        let id = Snapshot.Id.create_native ~created_at ~nonce |> Or_error.ok_exn in
        let snapshot = native_fixture ~codex_unresolved:unresolved ~id ~created_at in
        let summary =
          Thread_safe.block_on_async_exn (fun () ->
            Native_snapshot.save config ~socket_name:(Some "test") snapshot)
          |> Or_error.ok_exn
        in
        id, summary
      in
      let good_id, good = save "11111111" 1. String.Set.empty in
      let degraded_id, degraded = save "22222222" 2. (String.Set.singleton "%1") in
      assert good.last_good;
      assert degraded.latest;
      assert (not degraded.last_good);
      [%test_eq: string]
        (Core_unix.readlink (Filename.concat config.directory "latest"))
        (Snapshot.Id.to_string degraded_id);
      [%test_eq: string]
        (Core_unix.readlink (Filename.concat config.directory "last-good"))
        (Snapshot.Id.to_string good_id))
;;

let%test_unit "stable runtime sync retains a rollback pointer" =
  let root = Core_unix.mkdtemp "/tmp/tmux-recovery-runtime-XXXXXX" in
  Exn.protect
    ~finally:(fun () -> remove_tree root)
    ~f:(fun () ->
      let config : Runtime.config = { directory = root } in
      let stage source version =
        let plan =
          Thread_safe.block_on_async_exn (fun () -> Runtime.plan config ~source ~version)
          |> Or_error.ok_exn
        in
        Thread_safe.block_on_async_exn (fun () -> Runtime.apply config plan)
        |> Or_error.ok_exn;
        plan
      in
      let first = stage "/bin/echo" "1.0.0" in
      [%test_eq: string] (Core_unix.readlink first.current) "1.0.0";
      let second = stage "/bin/ls" "1.1.0" in
      [%test_eq: string] (Core_unix.readlink second.current) "1.1.0";
      [%test_eq: string] (Core_unix.readlink second.previous) "1.0.0";
      Thread_safe.block_on_async_exn (fun () -> Runtime.rollback config)
      |> Or_error.ok_exn;
      [%test_eq: string] (Core_unix.readlink second.current) "1.0.0";
      [%test_eq: string] (Core_unix.readlink second.previous) "1.1.0")
;;

let%test_unit "systemd telemetry is normalized for the service page" =
  let result =
    Systemd.service_result
      "Result=success\n\
       ExecMainExitTimestamp=Wed 2026-07-22 12:19:08 EDT\n\
       ExecMainStatus=0\n"
  and next =
    Systemd.next_run_of_json
      {|[{"next":1784737756705309,"unit":"tmux-recovery-save.timer"}]|}
  in
  [%test_eq: string option] result (Some "success · exit 0 · Wed 2026-07-22 12:19:08 EDT");
  [%test_eq: string option] next (Some "2026-07-22 16:29:16.705309000Z")
;;

let%test_unit "retention keeps a rolling maximum of ten native snapshots" =
  let day value = Time_ns.add Time_ns.epoch (Time_ns.Span.of_day (Float.of_int value)) in
  let summary position created_at ~last_good : Snapshot.summary =
    let id =
      Snapshot.Id.create_native ~created_at ~nonce:(sprintf "%08x" position)
      |> Or_error.ok_exn
    in
    { id
    ; created_at
    ; size_bytes = 1L
    ; latest = position = 0
    ; last_good
    ; validity = Valid
    ; warnings = []
    ; session_count = 1
    ; window_count = 1
    ; pane_count = 1
    ; manifest = true
    ; legacy = false
    }
  in
  let snapshots =
    List.init 12 ~f:(fun position ->
      summary position (day (99 - position)) ~last_good:(position = 0))
  in
  let config : Native_snapshot.config =
    { directory = "/fixtures/snapshots"
    ; runtime_directory = "/fixtures/run"
    ; maximum_snapshots = 10
    }
  in
  let catalog : Snapshot.catalog =
    { directory = config.directory; directory_exists = true; snapshots; warnings = [] }
  in
  let candidates = Native_snapshot.prune_candidates config ~now:(day 100) catalog in
  [%test_eq: int] (List.length candidates) 2;
  [%test_eq: Snapshot.Id.t] (List.hd_exn candidates).id (List.nth_exn snapshots 10).id;
  [%test_eq: Snapshot.Id.t] (List.last_exn candidates).id (List.nth_exn snapshots 11).id
;;

let%test_unit "pane capture keeps SGR color and neutralizes other controls" =
  let escape = Char.of_int_exn 27 in
  let raw =
    String.concat
      [ Char.to_string escape
      ; "[38;2;122;202;154mbtop"
      ; Char.to_string escape
      ; "[0m"
      ; Char.to_string escape
      ; "]52;c;clipboard"
      ; Char.to_string (Char.of_int_exn 7)
      ]
  in
  let sanitized = Tmux_adapter.sanitize_capture_line raw in
  assert (String.is_substring sanitized ~substring:"\027[38;2;122;202;154m");
  assert (String.is_substring sanitized ~substring:"\027[0m");
  assert (not (String.is_substring sanitized ~substring:"\027]52"));
  assert (not (String.exists sanitized ~f:(fun char -> Char.to_int char = 7)))
;;

let snapshot_id value = Snapshot.Id.of_string value |> Or_error.ok_exn

let valid_snapshot_lines =
  [ "pane\twork\t0\t1\t:*\t0\tshell\t:/tmp\t1\tzsh\t:zsh"
  ; "pane\twork\t0\t1\t:*\t1\tmonitor\t:/tmp\t0\tbtop\t:btop"
  ; "window\twork\t0\t:main\t1\t:*\tlayout\ton"
  ; "state\twork\twork"
  ]
;;

let%test_unit "resurrect summaries validate and count a saved graph" =
  let summary =
    Resurrect.summarize_lines
      ~id:(snapshot_id "tmux_resurrect_20260720T213239.txt")
      ~created_at:Time_ns.epoch
      ~size_bytes:123L
      ~latest:true
      ~manifest:false
      valid_snapshot_lines
  in
  [%test_eq: Snapshot.validity] summary.validity Valid;
  [%test_eq: int] summary.session_count 1;
  [%test_eq: int] summary.window_count 1;
  [%test_eq: int] summary.pane_count 2;
  assert summary.legacy
;;

let%test_unit "resurrect import builds a native workspace without executing saved \
               commands"
  =
  let id = snapshot_id "tmux_resurrect_20260720T213239.txt" in
  let workspace =
    Resurrect.workspace_of_lines ~id valid_snapshot_lines |> Or_error.ok_exn
  in
  [%test_eq: int] (Map.length workspace.sessions) 1;
  [%test_eq: int] (Map.length workspace.windows) 1;
  [%test_eq: int] (Map.length workspace.panes) 2;
  let btop = Map.data workspace.panes |> List.find_exn ~f:(fun pane -> pane.index = 1) in
  [%test_eq: string] btop.current_command "btop";
  [%test_eq: string] btop.cwd "/tmp"
;;

let%test_unit "malformed snapshots remain visible but invalid" =
  let summary =
    Resurrect.summarize_lines
      ~id:(snapshot_id "tmux_resurrect_20260720T213239.txt")
      ~created_at:Time_ns.epoch
      ~size_bytes:1L
      ~latest:false
      ~manifest:false
      [ "pane\ttoo-short" ]
  in
  match summary.validity with
  | Valid -> failwith "malformed snapshot unexpectedly passed validation"
  | Invalid errors ->
    assert (
      List.exists errors ~f:(String.is_substring ~substring:"expected at least 11 fields"))
;;

let%test_unit "empty and missing snapshot catalogs are explicit states" =
  let catalog =
    Resurrect.catalog_of_summaries
      ~directory:"/fixtures/missing"
      ~directory_exists:false
      ~current:None
      ~warnings:[ "snapshot directory does not exist" ]
      []
  in
  assert (List.is_empty catalog.snapshots);
  assert (not catalog.directory_exists);
  [%test_eq: int] (Snapshot.valid_count catalog) 0
;;

let%test_unit "an invalid latest snapshot does not replace last-good" =
  let older_id = snapshot_id "tmux_resurrect_20260720T210000.txt" in
  let newer_id = snapshot_id "tmux_resurrect_20260720T220000.txt" in
  let older =
    Resurrect.summarize_lines
      ~id:older_id
      ~created_at:Time_ns.epoch
      ~size_bytes:10L
      ~latest:false
      ~manifest:false
      valid_snapshot_lines
  and newer =
    Resurrect.summarize_lines
      ~id:newer_id
      ~created_at:Time_ns.epoch
      ~size_bytes:10L
      ~latest:true
      ~manifest:false
      [ "window\tbroken" ]
  in
  let catalog =
    Resurrect.catalog_of_summaries
      ~directory:"/fixtures/resurrect"
      ~directory_exists:true
      ~current:(Some newer_id)
      ~warnings:[]
      [ older; newer ]
  in
  let latest = List.hd_exn catalog.snapshots in
  let last_good = Snapshot.last_good catalog |> Option.value_exn in
  assert latest.latest;
  assert (not (Snapshot.is_valid latest));
  [%test_eq: string]
    (Snapshot.Id.to_string last_good.id)
    "tmux_resurrect_20260720T210000.txt"
;;

let plist ~label ~program ~extra =
  { Launchd.label
  ; path = "/fixtures/" ^ label ^ ".plist"
  ; contents =
      [%string
        "<plist><dict><key>Label</key><string>%{label}</string><key>ProgramArguments</key><array><string>%{program}</string></array>%{extra}</dict></plist>"]
  }
;;

let%test_unit "launchd reports the existing style of stack as legacy and loaded" =
  let save =
    plist
      ~label:"com.jonathan.tmux-resurrect-save"
      ~program:"/fixtures/bin/tmux-resurrect-save-safe"
      ~extra:"<key>StartInterval</key><integer>600</integer>"
  and restore =
    plist
      ~label:"com.jonathan.tmux"
      ~program:"/usr/bin/open"
      ~extra:"<key>RunAtLoad</key><true/>"
  in
  let status =
    Launchd.status_from_inventory
      { definitions = [ save; restore ]
      ; loaded = [ save.label, "0"; restore.label, "0" ]
      ; legacy_scripts = [ "/fixtures/bin/tmux-service" ]
      }
  in
  [%test_eq: Service.ownership] status.ownership Legacy;
  [%test_eq: Service.activation] status.periodic_save.activation Loaded;
  [%test_eq: string option]
    status.binary_path
    (Some "/fixtures/bin/tmux-resurrect-save-safe")
;;

let%test_unit "launchd marks mixed managed and legacy definitions as drifted" =
  let managed_save =
    plist
      ~label:"org.tmux-recovery.save"
      ~program:"/fixtures/bin/tmux-recovery"
      ~extra:"<key>StartInterval</key><integer>600</integer>"
  and managed_restore =
    plist
      ~label:"org.tmux-recovery.restore"
      ~program:"/fixtures/bin/tmux-recovery"
      ~extra:"<key>RunAtLoad</key><true/>"
  and legacy =
    plist ~label:"com.example.tmux-continuum" ~program:"/fixtures/bin/continuum" ~extra:""
  in
  let status =
    Launchd.status_from_inventory
      { definitions = [ managed_save; managed_restore; legacy ]
      ; loaded = [ legacy.label, "0" ]
      ; legacy_scripts = []
      }
  in
  [%test_eq: Service.ownership] status.ownership Drifted;
  [%test_eq: int] (List.length status.conflicts) 1
;;

let%test_unit "launchd has an explicit absent state" =
  let status =
    Launchd.status_from_inventory { definitions = []; loaded = []; legacy_scripts = [] }
  in
  [%test_eq: Service.ownership] status.ownership Absent;
  [%test_eq: Service.activation] status.periodic_save.activation Not_installed
;;

let%test_unit "managed launchd definitions call only the stable binary" =
  let config : Launchd.config =
    { launch_agents_directory = "/fixtures/LaunchAgents"
    ; bin_directory = "/fixtures/bin"
    }
  in
  let definitions =
    Launchd.managed_definitions
      config
      ~binary_path:"/managed/current/tmux-recovery"
      ~tmux_path:"/usr/bin/tmux"
      ~runtime_path:"/fixtures/node/bin:/usr/bin"
      ~log_directory:"/fixtures/log"
  in
  [%test_eq: int] (List.length definitions) 2;
  List.iter definitions ~f:(fun definition ->
    assert (
      String.is_substring
        definition.contents
        ~substring:"<string>/managed/current/tmux-recovery</string>");
    assert (not (String.is_substring definition.contents ~substring:"tmux-resurrect")));
  let restore = List.last_exn definitions in
  assert (String.is_substring restore.contents ~substring:"<string>restore</string>");
  assert (String.is_substring restore.contents ~substring:"<string>--if-empty</string>");
  assert (
    not (String.is_substring restore.contents ~substring:"<string>snapshots</string>"));
  assert (
    String.is_substring
      restore.contents
      ~substring:"<key>PATH</key>\n    <string>/fixtures/node/bin:/usr/bin</string>");
  let status =
    Launchd.status_from_inventory
      { definitions
      ; loaded = List.map definitions ~f:(fun definition -> definition.label, "0")
      ; legacy_scripts = []
      }
  in
  [%test_eq: string option]
    status.periodic_save.command
    (Some "tmux-recovery snapshot --trigger timer --quiet");
  [%test_eq: string option]
    status.login_restore.command
    (Some "tmux-recovery restore --approve --if-empty --quiet")
;;

let unit ~name ~contents = { Systemd.name; path = "/fixtures/systemd/" ^ name; contents }

let%test_unit "systemd fixtures normalize managed timer state" =
  let save =
    unit
      ~name:"tmux-recovery-save.timer"
      ~contents:
        "[Timer]\n\
         OnUnitActiveSec=10min\n\
         [Service]\n\
         ExecStart=/fixtures/bin/tmux-recovery snapshots save"
  and restore =
    unit
      ~name:"tmux-recovery-restore.service"
      ~contents:"[Service]\nExecStart=/fixtures/bin/tmux-recovery snapshots restore"
  in
  let status =
    Systemd.status_from_inventory
      { definitions = [ save; restore ]
      ; active = [ save.name ]
      ; enabled = [ save.name; restore.name ]
      ; legacy_scripts = []
      }
  in
  [%test_eq: Service.ownership] status.ownership Managed;
  [%test_eq: Service.activation] status.periodic_save.activation Loaded;
  [%test_eq: string option] status.periodic_save.schedule (Some "10min");
  [%test_eq: string option]
    status.periodic_save.command
    (Some "tmux-recovery snapshots save")
;;

let%test_unit "systemd prefers the timer over its inactive save service" =
  let save_service =
    unit
      ~name:"tmux-recovery-save.service"
      ~contents:
        "[Service]\n\
         ExecStart=/fixtures/bin/tmux-recovery snapshot --trigger timer --quiet"
  and save_timer =
    unit ~name:"tmux-recovery-save.timer" ~contents:"[Timer]\nOnUnitActiveSec=10min"
  and restore =
    unit
      ~name:"tmux-recovery-restore.service"
      ~contents:
        "[Service]\n\
         ExecStart=/fixtures/bin/tmux-recovery restore --approve --if-empty --quiet"
  in
  let status =
    Systemd.status_from_inventory
      { definitions = [ save_service; save_timer; restore ]
      ; active = [ save_timer.name; restore.name ]
      ; enabled = [ save_timer.name; restore.name ]
      ; legacy_scripts = []
      }
  in
  [%test_eq: Service.activation] status.periodic_save.activation Loaded;
  [%test_eq: string option] status.periodic_save.schedule (Some "10min");
  [%test_eq: string option]
    status.periodic_save.command
    (Some "tmux-recovery snapshot --trigger timer --quiet");
  [%test_eq: string option]
    status.login_restore.command
    (Some "tmux-recovery restore --approve --if-empty --quiet")
;;

let%test_unit "systemd recognizes legacy user units without adopting them" =
  let save =
    unit ~name:"tmux-resurrect-save.timer" ~contents:"[Timer]\nOnUnitActiveSec=10min"
  in
  let status =
    Systemd.status_from_inventory
      { definitions = [ save ]
      ; active = []
      ; enabled = [ save.name ]
      ; legacy_scripts = []
      }
  in
  [%test_eq: Service.ownership] status.ownership Legacy;
  [%test_eq: Service.activation] status.periodic_save.activation Installed
;;

let%test_unit "managed systemd units use direct native entrypoints" =
  let config : Systemd.config =
    { unit_directory = "/fixtures/systemd"; bin_directory = "/fixtures/bin" }
  in
  let definitions =
    Systemd.managed_definitions
      config
      ~binary_path:"/managed/current/tmux-recovery"
      ~tmux_path:"/usr/bin/tmux"
      ~runtime_path:"/fixtures/node/bin:/usr/bin"
  in
  [%test_eq: int] (List.length definitions) 3;
  let contents = List.map definitions ~f:(fun item -> item.contents) |> String.concat in
  assert (
    String.is_substring
      contents
      ~substring:"ExecStart=/managed/current/tmux-recovery snapshot");
  assert (
    String.is_substring
      contents
      ~substring:"ExecStart=/managed/current/tmux-recovery restore --approve");
  assert (not (String.is_substring contents ~substring:"tmux-recovery snapshots"));
  assert (String.is_substring contents ~substring:"RandomizedDelaySec=30s");
  assert (
    String.is_substring
      contents
      ~substring:"Environment=\"PATH=/fixtures/node/bin:/usr/bin\"");
  assert (not (String.is_substring contents ~substring:"tmux-resurrect-save-safe"));
  let status =
    Systemd.status_from_inventory
      { definitions
      ; active = [ "tmux-recovery-save.timer"; "tmux-recovery-restore.service" ]
      ; enabled = [ "tmux-recovery-save.timer"; "tmux-recovery-restore.service" ]
      ; legacy_scripts = []
      }
  in
  [%test_eq: string option]
    status.periodic_save.command
    (Some "tmux-recovery snapshot --trigger timer --quiet");
  [%test_eq: string option]
    status.login_restore.command
    (Some "tmux-recovery restore --approve --if-empty --quiet")
;;
