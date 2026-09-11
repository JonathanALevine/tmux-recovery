open! Core
open Bonsai_term
module Handle = Bonsai_test.Handle
module Fixture = Tmux_recovery_tui_fixture.Tui_fixture

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

let detail handle =
  Handle.show_into_string handle
  |> String.split_lines
  |> List.filter_map ~f:(fun line ->
    Option.map (String.substr_index line ~pattern:"┃") ~f:(fun index ->
      String.drop_prefix line (index + String.length "┃")))
  |> String.concat ~sep:"\n"
;;

let%test_unit "Status expands like Sessions and each section owns its detail view" =
  let handle = status_handle Fixture.warning_app in
  let rendered () = Handle.show_into_string handle in
  let root = rendered () in
  assert (String.is_substring root ~substring:"▾ Status");
  assert (String.is_substring root ~substring:"Affected panes  [1]");
  assert (not (String.is_substring (detail handle) ~substring:"Cause:"));
  send handle Enter;
  assert (String.is_substring (rendered ()) ~substring:"▸ Status");
  assert (not (String.is_substring (rendered ()) ~substring:"Recovery safety"));
  (* Expansion and selecting the first section may happen before the next frame. *)
  List.iter [ Event.Key.Enter; Arrow `Down ] ~f:(fun key ->
    Bonsai_term_test.send_event handle (Key_press { key; mods = [] }));
  Handle.recompute_view_until_stable handle;
  let sections =
    [ "Recovery", "tmux: PASS", "Cause:"
    ; "Affected panes (1)", "Cause: Codex has no durable thread ID.", "Native history:"
    ; "Snapshots", "Native history:", "Periodic save:"
    ; "Automation", "Periodic save:", "Pending actions:"
    ; "Autonomous cleanup", "Pending actions:", "Native history:"
    ; "Recovery safety", "Snapshot integrity and occupied targets", "Policy:"
    ]
  in
  List.iteri sections ~f:(fun index (title, contents, excluded) ->
    let right = detail handle in
    assert (String.is_substring right ~substring:title);
    assert (String.is_substring right ~substring:contents);
    assert (not (String.is_substring right ~substring:excluded));
    let navigation = rendered () in
    send handle Enter;
    if index = 1
    then (
      assert (String.is_substring (rendered ()) ~substring:"▾ Affected panes");
      send handle Enter);
    [%test_eq: string] (rendered ()) navigation;
    send handle Tab;
    let focused = rendered () in
    assert (String.is_substring focused ~substring:"Tab navigation");
    send handle Enter;
    [%test_eq: string] (rendered ()) focused;
    send handle Tab;
    [%test_eq: string] (rendered ()) navigation;
    if index < List.length sections - 1 then send handle (Arrow `Down));
  let last = rendered () in
  send handle (Arrow `Down);
  [%test_eq: string] (rendered ()) last;
  for _ = 1 to 6 do
    send handle (Arrow `Up)
  done;
  [%test_eq: string] (rendered ()) root;
  send handle Enter;
  send handle Enter;
  [%test_eq: string] (rendered ()) root
;;

let%test_unit "section selection survives refresh and unavailable data stays in its \
               section"
  =
  let workspace, recovery, snapshots, services = Fixture.initial_data in
  let app =
    Fixture.make_app_with_reload
      ~initial_data:(workspace, recovery, snapshots, services)
      ~reload:(fun () ->
        Effect.return
          ( Or_error.error_string "fixture workspace"
          , recovery
          , Or_error.error_string "fixture snapshots unavailable"
          , Or_error.error_string "fixture automation unavailable" ))
      ()
  in
  let handle = status_handle app in
  for _ = 1 to 3 do
    send handle (Arrow `Down)
  done;
  assert (String.is_substring (detail handle) ~substring:"Native history:");
  send handle Tab;
  send handle (ASCII 'r');
  let right = detail handle in
  assert (String.is_substring right ~substring:"snapshot inventory unavailable");
  assert (String.is_substring right ~substring:"fixture snapshots unavailable");
  assert (not (String.is_substring right ~substring:"fixture automation unavailable"));
  send handle Tab;
  send handle (Arrow `Down);
  assert (
    String.is_substring (detail handle) ~substring:"service manager status unavailable");
  assert (String.is_substring (detail handle) ~substring:"fixture automation unavailable");
  for _ = 1 to 4 do
    send handle (Arrow `Up)
  done;
  send handle Enter;
  let collapsed = Handle.show_into_string handle in
  assert (String.is_substring collapsed ~substring:"▸ Status");
  assert (not (String.is_substring collapsed ~substring:"Recovery safety"))
;;

let%test_unit "narrow section details keep selection and scrolling; navigation resets \
               offset"
  =
  let handle = status_handle Fixture.many_warnings_app in
  send handle (Arrow `Down);
  send handle (Arrow `Down);
  send handle Tab;
  resize handle 40 14;
  for _ = 1 to 30 do
    send handle (Arrow `Down)
  done;
  let before = Handle.show_into_string handle in
  send handle Enter;
  [%test_eq: string] (Handle.show_into_string handle) before;
  assert (String.is_substring before ~substring:"Affected panes  [30]");
  assert (String.is_substring before ~substring:"Tab navigation");
  send handle Tab;
  send handle (Arrow `Down);
  resize handle 100 22;
  assert (String.is_substring (detail handle) ~substring:"Native history:");
  assert (not (String.is_substring (detail handle) ~substring:"Cause:"));
  send handle (Arrow `Up);
  assert (String.is_substring (detail handle) ~substring:"Affected panes (30)");
  assert (String.is_substring (detail handle) ~substring:"development:0.0 · %1")
;;
