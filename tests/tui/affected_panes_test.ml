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

let select_affected handle =
  for _ = 1 to 4 do
    send handle (Arrow `Down)
  done
;;

let%test_unit "affected panes is a collapsed branch with selectable recovery details" =
  let handle = Bonsai_term_test.create_handle Fixture.many_warnings_app in
  resize handle 100 22;
  select_affected handle;
  let rendered () = Handle.show_into_string handle in
  let collapsed = rendered () in
  assert (String.is_substring collapsed ~substring:"▸ Affected panes  [30]");
  assert (not (String.is_substring collapsed ~substring:"development:0.0"));
  send handle Enter;
  assert (String.is_substring (rendered ()) ~substring:"▾ Affected panes  [30]");
  assert (String.is_substring (rendered ()) ~substring:"development:0.0 · codex");
  send handle Enter;
  [%test_eq: string] (rendered ()) collapsed;
  (* Expansion and movement must use the latest state even within one frame. *)
  List.iter [ Event.Key.Enter; Arrow `Down ] ~f:(fun key ->
    Bonsai_term_test.send_event handle (Key_press { key; mods = [] }));
  Handle.recompute_view_until_stable handle;
  for index = 1 to 30 do
    let contents = rendered () in
    assert (String.is_substring contents ~substring:[%string "Pane: %%{index#Int}"]);
    assert (String.is_substring contents ~substring:"Application: codex");
    assert (
      String.is_substring
        contents
        ~substring:[%string "Cause: Cannot resume application in pane %%{index#Int}."]);
    assert (String.is_substring contents ~substring:"Recovery: shell only;");
    send handle Enter;
    [%test_eq: string] (rendered ()) contents;
    if index < 30 then send handle (Arrow `Down)
  done;
  let last = rendered () in
  send handle (Arrow `Down);
  [%test_eq: string] (rendered ()) last;
  resize handle 40 14;
  assert (String.is_substring (rendered ()) ~substring:"development:0.29");
  send handle Tab;
  for _ = 1 to 30 do
    send handle (Arrow `Down)
  done;
  assert (String.is_substring (rendered ()) ~substring:"will not resume.");
  assert (String.is_substring (rendered ()) ~substring:"Tab navigation");
  let detail = rendered () in
  send handle Enter;
  [%test_eq: string] (rendered ()) detail;
  send handle Tab;
  resize handle 100 22;
  for _ = 1 to 30 do
    send handle (Arrow `Up)
  done;
  send handle Enter;
  [%test_eq: string] (rendered ()) collapsed
;;

let%test_unit "affected pane identities do not select the same pane under Sessions" =
  let handle = Bonsai_term_test.create_handle Fixture.many_warnings_app in
  resize handle 100 22;
  List.iter
    [ Event.Key.Arrow `Down; Arrow `Down; Enter; Arrow `Down; Enter; Arrow `Down ]
    ~f:(send handle);
  assert (String.is_substring (Handle.show_into_string handle) ~substring:"PREVIEW");
  for _ = 1 to 100 do
    send handle (Arrow `Down)
  done;
  send handle Enter;
  send handle (Arrow `Down);
  let contents = Handle.show_into_string handle in
  assert (
    String.is_substring contents ~substring:"Cause: Cannot resume application in pane %1.");
  assert (not (String.is_substring contents ~substring:"PREVIEW"))
;;

let refreshed_handle recovery =
  let _, _, snapshots, services = Fixture.many_warnings_data in
  let handle =
    Bonsai_term_test.create_handle
      (Fixture.make_app_with_reload
         ~initial_data:Fixture.many_warnings_data
         ~reload:(fun () ->
           (* Replace the plan without running an autonomy reconciliation. *)
           Effect.return
             (Or_error.error_string "fixture workspace", Ok recovery, snapshots, services))
         ())
  in
  resize handle 100 22;
  select_affected handle;
  send handle Enter;
  send handle (Arrow `Down);
  handle
;;

let%test_unit "refresh preserves surviving selection and falls back when a pane recovers" =
  let _, recovery, _, _ = Fixture.many_warnings_data in
  let recovery = Or_error.ok_exn recovery in
  let recovered_first =
    { recovery with
      decisions =
        List.map recovery.decisions ~f:(fun decision ->
          if String.equal decision.Recovery.pane_id "%1"
          then { decision with action = Restart }
          else decision)
    }
  in
  let surviving = refreshed_handle recovered_first in
  send surviving (Arrow `Down);
  send surviving (ASCII 'r');
  assert (String.is_substring (Handle.show_into_string surviving) ~substring:"Pane: %2");
  let recovered = refreshed_handle recovered_first in
  send recovered Tab;
  send recovered (ASCII 'r');
  let contents = Handle.show_into_string recovered in
  assert (String.is_substring contents ~substring:"Affected panes (29)");
  assert (String.is_substring contents ~substring:"Tab navigation");
  assert (String.is_substring contents ~substring:"▾ Affected panes  [29]");
  let all_recovered =
    { recovery with
      decisions =
        List.map recovery.decisions ~f:(fun decision ->
          { decision with action = Restart })
    }
  in
  let empty = refreshed_handle all_recovered in
  send empty (ASCII 'r');
  let contents = Handle.show_into_string empty in
  assert (String.is_substring contents ~substring:"Affected panes (0)");
  assert (
    String.is_substring contents ~substring:"No applications require shell-only recovery.");
  send empty Enter;
  [%test_eq: string] (Handle.show_into_string empty) contents
;;
