open! Core
open Bonsai_term
module Handle = Bonsai_test.Handle
module Fixture = Tmux_recovery_tui_fixture.Tui_fixture

let send handle key =
  Bonsai_term_test.send_event handle (Key_press { key; mods = [] });
  Handle.recompute_view_until_stable handle
;;

let select_pane handle =
  List.iter
    [ Event.Key.Arrow `Down; Arrow `Down; Enter; Arrow `Down; Enter; Arrow `Down ]
    ~f:(send handle)
;;

let%test_unit "Enter toggles branches, leaves and horizontal arrows do nothing" =
  let handle = Bonsai_term_test.create_handle Fixture.app in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  let rendered () = Handle.show_into_string handle in
  let initial = rendered () in
  List.iter [ Event.Key.Enter; Arrow `Left; Arrow `Right ] ~f:(fun key ->
    send handle key;
    [%test_eq: string] (rendered ()) initial);
  send handle (Arrow `Down);
  let expanded = rendered () in
  assert (String.is_substring expanded ~substring:"development");
  send handle Enter;
  let collapsed = rendered () in
  assert (not (String.is_substring collapsed ~substring:"development"));
  List.iter [ Event.Key.Arrow `Left; Arrow `Right ] ~f:(fun key ->
    send handle key;
    [%test_eq: string] (rendered ()) collapsed);
  send handle Enter;
  [%test_eq: string] (rendered ()) expanded;
  send handle (Arrow `Down);
  assert (String.is_substring (rendered ()) ~substring:"Typed ID: $1");
  send handle Enter;
  assert (String.is_substring (rendered ()) ~substring:"0:monitoring");
  send handle (Arrow `Down);
  assert (String.is_substring (rendered ()) ~substring:"latest btop output");
  send handle Enter;
  send handle (Arrow `Down);
  send handle Enter;
  send handle (Arrow `Down);
  let application = rendered () in
  assert (String.is_substring application ~substring:"Action: restart");
  List.iter [ Event.Key.Enter; Arrow `Left; Arrow `Right ] ~f:(fun key ->
    send handle key;
    [%test_eq: string] (rendered ()) application);
  send handle (Arrow `Up);
  assert (String.is_substring (rendered ()) ~substring:"Typed ID: %1");
  send handle Enter;
  send handle (Arrow `Down);
  assert (String.is_substring (rendered ()) ~substring:"Recovery readiness");
  ()
;;

let%test_unit "narrow layouts keep the selected pane and its preview visible" =
  let handle = Bonsai_term_test.create_handle Fixture.app in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  Handle.recompute_view_until_stable handle;
  select_pane handle;
  let rendered () = Handle.show_into_string handle in
  let wide = rendered () in
  List.iter
    [ 60, 22; 40, 14; 83, 22; 84, 22 ]
    ~f:(fun (width, height) ->
      Bonsai_term_test.set_dimensions handle { width; height };
      let contents = rendered () in
      assert (String.is_substring contents ~substring:"NAVIGATION");
      assert (String.is_substring contents ~substring:"PREVIEW");
      assert (String.is_substring contents ~substring:"pane 0");
      assert (String.is_substring contents ~substring:"latest btop output");
      let dimensions = View.dimensions (Bonsai_term_test.last_view handle) in
      [%test_eq: int] dimensions.width width;
      [%test_eq: int] dimensions.height height);
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  [%test_eq: string] (rendered ()) wide;
  ()
;;

let%test_unit "refresh retains the selected page and recaptures its preview" =
  let captures = ref 0 in
  let capture_pane ~pane_id =
    Effect.of_sync_fun
      (fun () ->
        incr captures;
        Ok [ [%string "capture %{!captures#Int} for %{pane_id}"] ])
      ()
  in
  let reload () =
    (* An unavailable plan keeps this test out of the autonomy tick while still replacing
       the workspace with the same identities. *)
    let workspace, _, snapshots, services = Fixture.initial_data in
    Effect.return (workspace, Or_error.error_string "fixture plan", snapshots, services)
  in
  let exits = ref 0 in
  let exit () = Effect.of_sync_fun (fun () -> incr exits) () in
  let handle =
    Bonsai_term_test.create_handle
      (Fixture.make_app_with_reload ~capture_pane ~reload ~exit ())
  in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  Handle.recompute_view_until_stable handle;
  select_pane handle;
  let rendered () = Handle.show_into_string handle in
  assert (String.is_substring (rendered ()) ~substring:"capture 1 for %1");
  send handle Tab;
  send handle (ASCII 'r');
  assert (String.is_substring (rendered ()) ~substring:"capture 2 for %1");
  assert (String.is_substring (rendered ()) ~substring:"Typed ID: %1");
  assert (String.is_substring (rendered ()) ~substring:"● PREVIEW");
  send handle (ASCII 'q');
  Bonsai_term_test.send_event handle (Key_press { key = ASCII 'c'; mods = [ Ctrl ] });
  Handle.recompute_view_until_stable handle;
  [%test_eq: int] !exits 2;
  ()
;;

let%test_unit "late preview responses cannot replace a newer selection request" =
  let pending = Queue.create () in
  let capture_pane ~pane_id:_ =
    let response = Effect.For_testing.Svar.create () in
    Queue.enqueue pending response;
    Effect.For_testing.of_svar_fun (fun () -> response) ()
  in
  let reload () = Effect.return Fixture.initial_data in
  let handle =
    Bonsai_term_test.create_handle (Fixture.make_app_with_reload ~capture_pane ~reload ())
  in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  Handle.recompute_view_until_stable handle;
  select_pane handle;
  let first = Queue.dequeue_exn pending in
  let rendered () = Handle.show_into_string handle in
  assert (String.is_substring (rendered ()) ~substring:"Capturing current pane");
  send handle (Arrow `Down);
  send handle (Arrow `Up);
  let second = Queue.dequeue_exn pending in
  Effect.For_testing.Svar.fill_if_empty first (Ok [ "outdated output" ]);
  Handle.recompute_view_until_stable handle;
  let loading = rendered () in
  assert (String.is_substring loading ~substring:"Capturing current pane");
  assert (not (String.is_substring loading ~substring:"outdated output"));
  Effect.For_testing.Svar.fill_if_empty second (Ok [ "current output" ]);
  Handle.recompute_view_until_stable handle;
  assert (String.is_substring (rendered ()) ~substring:"current output");
  send handle (Arrow `Down);
  send handle (Arrow `Up);
  let third = Queue.dequeue_exn pending in
  Effect.For_testing.Svar.fill_if_empty third (Or_error.error_string "capture failed");
  Handle.recompute_view_until_stable handle;
  assert (
    String.is_substring (rendered ()) ~substring:"Preview unavailable: capture failed");
  ()
;;
