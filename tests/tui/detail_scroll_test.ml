open! Core
open Bonsai_term
module Handle = Bonsai_test.Handle
module Fixture = Tmux_recovery_tui_fixture.Tui_fixture

let send handle key =
  Bonsai_term_test.send_event handle (Key_press { key; mods = [] });
  Handle.recompute_view_until_stable handle
;;

let select_status handle =
  List.iter [ Event.Key.Arrow `Down; Arrow `Down; Arrow `Down ] ~f:(send handle)
;;

let resize handle width height =
  Bonsai_term_test.set_dimensions handle { width; height };
  Handle.recompute_view_until_stable handle
;;

let%test_unit "only Tab changes focus; detail keys never change tree selection" =
  let handle = Bonsai_term_test.create_handle Fixture.app in
  resize handle 100 22;
  send handle (Arrow `Down);
  let rendered () = Handle.show_into_string handle in
  let navigation = rendered () in
  assert (String.is_substring navigation ~substring:"▶ NAVIGATION");
  send handle Tab;
  let detail = rendered () in
  assert (String.is_substring detail ~substring:"▶ DETAIL");
  List.iter
    [ Event.Key.Enter; Arrow `Down; Arrow `Up; Arrow `Left; Arrow `Right ]
    ~f:(fun key ->
      send handle key;
      [%test_eq: string] (rendered ()) detail);
  Bonsai_term_test.send_event handle (Key_press { key = Tab; mods = [ Shift ] });
  Handle.recompute_view_until_stable handle;
  [%test_eq: string] (rendered ()) detail;
  send handle Tab;
  [%test_eq: string] (rendered ()) navigation;
  List.iter [ Event.Key.Tab; Enter; Arrow `Down ] ~f:(fun key ->
    Bonsai_term_test.send_event handle (Key_press { key; mods = [] }));
  Handle.recompute_view_until_stable handle;
  [%test_eq: string] (rendered ()) detail;
  send handle Tab;
  Bonsai_term_test.send_event handle (Key_press { key = Tab; mods = [ Shift ] });
  Handle.recompute_view_until_stable handle;
  [%test_eq: string] (rendered ()) navigation;
  List.iter [ Event.Key.Page `Down; Page `Up; Home; End ] ~f:(fun key ->
    send handle key;
    [%test_eq: string] (rendered ()) navigation);
  send handle Enter;
  assert (not (String.is_substring (rendered ()) ~substring:"development"))
;;

let%test_unit "all affected panes and later status sections are reachable" =
  let handle = Bonsai_term_test.create_handle Fixture.many_warnings_app in
  resize handle 100 22;
  select_status handle;
  send handle Tab;
  let rendered () = Handle.show_into_string handle in
  let top = rendered () in
  assert (String.is_substring top ~substring:"Affected panes (30)");
  assert (String.is_substring top ~substring:"Application: codex");
  assert (
    String.is_substring top ~substring:"Cause: Cannot resume application in pane %1.");
  assert (String.is_substring top ~substring:"Recovery: shell only;");
  send handle (Arrow `Up);
  [%test_eq: string] (rendered ()) top;
  List.iter [ Event.Key.Page `Down; Page `Up ] ~f:(fun key ->
    send handle key;
    [%test_eq: string] (rendered ()) top);
  let contents = Buffer.create 10000 in
  for _ = 1 to 250 do
    Buffer.add_string contents (rendered ());
    send handle (Arrow `Down)
  done;
  let contents = Buffer.contents contents in
  for index = 0 to 29 do
    assert (
      String.is_substring
        contents
        ~substring:[%string "development:0.%{index#Int} · %%{index + 1#Int}"])
  done;
  let bottom = rendered () in
  assert (String.is_substring bottom ~substring:"Recovery safety:");
  assert (String.is_substring contents ~substring:"Pending actions:");
  assert (String.is_substring contents ~substring:"Snapshots");
  assert (String.is_substring contents ~substring:"Automation");
  send handle (Arrow `Down);
  [%test_eq: string] (rendered ()) bottom;
  send handle (Page `Up);
  [%test_eq: string] (rendered ()) bottom;
  send handle (Page `Down);
  [%test_eq: string] (rendered ()) bottom;
  send handle Home;
  [%test_eq: string] (rendered ()) top;
  (* Several key events can arrive before Bonsai draws the next frame. *)
  for _ = 1 to 5 do
    Bonsai_term_test.send_event handle (Key_press { key = Arrow `Down; mods = [] })
  done;
  Handle.recompute_view_until_stable handle;
  let rapid = rendered () in
  send handle Home;
  for _ = 1 to 5 do
    send handle (Arrow `Down)
  done;
  [%test_eq: string] (rendered ()) rapid;
  send handle End;
  [%test_eq: string] (rendered ()) bottom;
  send handle Tab;
  send handle (Arrow `Up);
  assert (String.is_substring (rendered ()) ~substring:"Typed ID: $1");
  send handle (Arrow `Down);
  send handle Tab;
  [%test_eq: string] (rendered ()) top
;;

let%test_unit "status has an explicit unaffected state and the specific Codex cause" =
  let handle = Bonsai_term_test.create_handle Fixture.app in
  resize handle 100 22;
  select_status handle;
  let contents = Handle.show_into_string handle in
  assert (String.is_substring contents ~substring:"Affected panes (0)");
  assert (
    String.is_substring contents ~substring:"No applications require shell-only recovery.");
  let warning = Bonsai_term_test.create_handle Fixture.warning_app in
  resize warning 100 22;
  select_status warning;
  let contents = Handle.show_into_string warning in
  assert (String.is_substring contents ~substring:"Affected panes (1)");
  assert (String.is_substring contents ~substring:"Cause: Codex has no durable thread ID.")
;;

let%test_unit "refresh and resize retain focus and clamp the scroll offset" =
  let data = ref Fixture.many_warnings_data in
  let reload () =
    let workspace, _, snapshots, services = !data in
    (* Keep the test synchronous and isolated from autonomy reconciliation. *)
    Effect.return (workspace, Or_error.error_string "fixture plan", snapshots, services)
  in
  let handle =
    Bonsai_term_test.create_handle
      (Fixture.make_app_with_reload ~initial_data:!data ~reload ())
  in
  resize handle 100 22;
  select_status handle;
  send handle Tab;
  for _ = 1 to 19 do
    send handle (Arrow `Down)
  done;
  let rendered () = Handle.show_into_string handle in
  let before = rendered () in
  assert (String.is_substring before ~substring:"development:0.4");
  send handle (ASCII 'r');
  assert (String.is_substring (rendered ()) ~substring:"development:0.4");
  assert (String.is_substring (rendered ()) ~substring:"▶ DETAIL");
  List.iter
    [ 40, 14; 60, 22; 83, 22; 84, 22; 100, 22 ]
    ~f:(fun (width, height) ->
      resize handle width height;
      let contents = rendered () in
      assert (String.is_substring contents ~substring:"NAVIGATION");
      assert (String.is_substring contents ~substring:"▶ DETAIL");
      send handle End;
      send handle (Arrow `Down);
      [%test_eq: Dimensions.t]
        (View.dimensions (Bonsai_term_test.last_view handle))
        { width; height });
  resize handle 100 500;
  assert (String.is_substring (rendered ()) ~substring:"Affected panes (30)");
  resize handle 100 22;
  assert (String.is_substring (rendered ()) ~substring:"▶ DETAIL · 1–");
  (* A fresh handle starts a separate refresh after its selected session disappears. *)
  let missing =
    Bonsai_term_test.create_handle
      (Fixture.make_app_with_reload ~initial_data:Fixture.many_warnings_data ~reload ())
  in
  resize missing 100 22;
  send missing (Arrow `Down);
  send missing (Arrow `Down);
  send missing Tab;
  let workspace, recovery, snapshots, services = Fixture.initial_data in
  let workspace = Or_error.ok_exn workspace in
  let empty =
    Tmux_recovery_domain.Workspace.create
      ~source:workspace.source
      ~server:workspace.server
      []
      []
      []
      []
    |> Result.map_error ~f:(String.concat ~sep:"; ")
    |> Result.ok_or_failwith
  in
  data := Ok empty, recovery, snapshots, services;
  send missing (ASCII 'r');
  let contents = Handle.show_into_string missing in
  assert (String.is_substring contents ~substring:"▶ DETAIL");
  assert (String.is_substring contents ~substring:"tmux-recovery")
;;

let%test_unit "a shorter refreshed status clamps scrolling without losing focus" =
  let handle =
    Bonsai_term_test.create_handle
      (Fixture.make_app_with_reload
         ~initial_data:Fixture.many_warnings_data
         ~reload:(fun () -> Effect.return Fixture.initial_data)
         ())
  in
  resize handle 100 22;
  select_status handle;
  send handle Tab;
  send handle End;
  send handle (ASCII 'r');
  let rendered () = Handle.show_into_string handle in
  let refreshed = rendered () in
  assert (String.is_substring refreshed ~substring:"▶ DETAIL");
  assert (String.is_substring refreshed ~substring:"Recovery safety:");
  send handle (Arrow `Down);
  [%test_eq: string] (rendered ()) refreshed;
  send handle Home;
  assert (String.is_substring (rendered ()) ~substring:"Affected panes (0)")
;;
