open! Core
open Bonsai_term
module Handle = Bonsai_test.Handle
module Fixture = Tmux_recovery_tui_fixture.Tui_fixture
module Recovery = Tmux_recovery_domain.Recovery

let send handle key =
  Bonsai_term_test.send_event handle (Key_press { key; mods = [] });
  Handle.recompute_view_until_stable handle
;;

let resize handle width height =
  Bonsai_term_test.set_dimensions handle { width; height };
  Handle.recompute_view_until_stable handle
;;

let status_handle app =
  let handle = Bonsai_term_test.create_handle app in
  resize handle 100 22;
  for _ = 1 to 3 do
    send handle (Arrow `Down)
  done;
  handle
;;

let%test_unit "affected panes stays in Status details and only Detail Enter toggles it" =
  let handle = status_handle Fixture.warning_app in
  let rendered () = Handle.show_into_string handle in
  let navigation = rendered () in
  assert (String.is_substring navigation ~substring:"▾ Affected panes (1)");
  assert (String.is_substring navigation ~substring:"shell fallback(s) · details");
  assert (
    String.is_substring navigation ~substring:"Cause: Codex has no durable thread ID.");
  assert (not (String.is_substring navigation ~substring:"Select Affected panes"));
  (* Status remains a leaf in navigation. *)
  send handle Enter;
  send handle (Arrow `Down);
  [%test_eq: string] (rendered ()) navigation;
  (* Focus changes and toggles can arrive before the next frame. *)
  List.iter [ Event.Key.Tab; Enter ] ~f:(fun key ->
    Bonsai_term_test.send_event handle (Key_press { key; mods = [] }));
  Handle.recompute_view_until_stable handle;
  let collapsed = rendered () in
  assert (String.is_substring collapsed ~substring:"▸ Affected panes (1)");
  assert (not (String.is_substring collapsed ~substring:"Cause:"));
  assert (String.is_substring collapsed ~substring:"Enter affected panes");
  assert (String.is_substring collapsed ~substring:"Snapshots");
  send handle Enter;
  let expanded = rendered () in
  assert (String.is_substring expanded ~substring:"▾ Affected panes (1)");
  assert (String.is_substring expanded ~substring:"Cause: Codex has no durable thread ID.");
  send handle Tab;
  [%test_eq: string] (rendered ()) navigation;
  send handle (Arrow `Up);
  send handle (Arrow `Down);
  send handle Tab;
  [%test_eq: string] (rendered ()) expanded
;;

let%test_unit "all affected pane records and later Status sections are scrollable" =
  let handle = status_handle Fixture.many_warnings_app in
  send handle Tab;
  let contents = Buffer.create 20000 in
  for _ = 1 to 400 do
    Buffer.add_string contents (Handle.show_into_string handle);
    send handle (Arrow `Down)
  done;
  let contents = Buffer.contents contents in
  for index = 1 to 30 do
    assert (
      String.is_substring
        contents
        ~substring:[%string "development:0.%{index - 1#Int} · %%{index#Int}"]);
    assert (
      String.is_substring
        contents
        ~substring:[%string "Cause: Cannot resume application in pane %%{index#Int}."])
  done;
  assert (String.is_substring contents ~substring:"Application: codex");
  assert (String.is_substring contents ~substring:"Recovery: shell only;");
  assert (String.is_substring contents ~substring:"Snapshots");
  assert (String.is_substring contents ~substring:"Automation");
  assert (String.is_substring contents ~substring:"Recovery safety:");
  (* Closing from below the list returns its heading to view. *)
  send handle Enter;
  assert (
    String.is_substring
      (Handle.show_into_string handle)
      ~substring:"▸ Affected panes (30)");
  resize handle 40 14;
  send handle Enter;
  assert (
    String.is_substring
      (Handle.show_into_string handle)
      ~substring:"▾ Affected panes (30)");
  for _ = 1 to 10 do
    send handle (Arrow `Down)
  done;
  send handle Enter;
  assert (
    String.is_substring
      (Handle.show_into_string handle)
      ~substring:"▸ Affected panes (30)");
  assert (String.is_substring (Handle.show_into_string handle) ~substring:"Tab navigation")
;;

let%test_unit "refresh preserves list state and clamps scrolling when affected panes \
               recover"
  =
  let workspace, recovery, snapshots, services = Fixture.many_warnings_data in
  let recovery = Or_error.ok_exn recovery in
  let recovered =
    { recovery with
      decisions =
        List.map recovery.decisions ~f:(fun decision ->
          { decision with action = Restart })
    }
  in
  let make initial refreshed =
    status_handle
      (Fixture.make_app_with_reload
         ~initial_data:(workspace, Ok initial, snapshots, services)
         ~reload:(fun () ->
           Effect.return
             (Or_error.error_string "fixture workspace", Ok refreshed, snapshots, services))
         ())
  in
  (* Each independent refresh uses a fresh fixture handle. *)
  let collapsed = make recovery recovery in
  send collapsed Tab;
  send collapsed Enter;
  send collapsed (ASCII 'r');
  assert (
    String.is_substring
      (Handle.show_into_string collapsed)
      ~substring:"▸ Affected panes (30)");
  let handle = make recovery recovered in
  send handle Tab;
  for _ = 1 to 400 do
    send handle (Arrow `Down)
  done;
  send handle (ASCII 'r');
  let bottom = Handle.show_into_string handle in
  assert (String.is_substring bottom ~substring:"Recovery safety:");
  assert (String.is_substring bottom ~substring:"Tab navigation");
  send handle (Arrow `Down);
  [%test_eq: string] (Handle.show_into_string handle) bottom;
  for _ = 1 to 100 do
    send handle (Arrow `Up)
  done;
  let empty = Handle.show_into_string handle in
  assert (String.is_substring empty ~substring:"Affected panes (0)");
  assert (
    String.is_substring empty ~substring:"No applications require shell-only recovery.");
  assert (not (String.is_substring empty ~substring:"Enter affected panes"));
  send handle Enter;
  [%test_eq: string] (Handle.show_into_string handle) empty;
  let reappeared = make recovered recovery in
  send reappeared Tab;
  send reappeared (ASCII 'r');
  assert (
    String.is_substring
      (Handle.show_into_string reappeared)
      ~substring:"▾ Affected panes (30)")
;;

let%test_unit "batched Status selection, focus, and Enter use current selection" =
  let handle = Bonsai_term_test.create_handle Fixture.warning_app in
  resize handle 100 22;
  List.iter [ Event.Key.Arrow `Down; Arrow `Down; Arrow `Down; Tab; Enter ] ~f:(fun key ->
    Bonsai_term_test.send_event handle (Key_press { key; mods = [] }));
  Handle.recompute_view_until_stable handle;
  assert (
    String.is_substring (Handle.show_into_string handle) ~substring:"▸ Affected panes (1)");
  assert (String.is_substring (Handle.show_into_string handle) ~substring:"Tab navigation")
;;
