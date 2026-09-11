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

let affected_handle app =
  let handle = Bonsai_term_test.create_handle app in
  resize handle 100 22;
  for _ = 1 to 5 do
    send handle (Arrow `Down)
  done;
  handle
;;

let%test_unit "Status labels and affected-list arrow align with Sessions" =
  let handle = affected_handle Fixture.warning_app in
  let rendered = Handle.show_into_string handle in
  let column label =
    String.split_lines rendered
    |> List.filter_map ~f:(fun line ->
      Option.map (String.substr_index line ~pattern:"┃") ~f:(fun index ->
        String.prefix line index))
    |> List.find_map_exn ~f:(fun line ->
      Option.map (String.substr_index line ~pattern:label) ~f:(fun index ->
        View.width (View.text (String.prefix line index))))
  in
  List.iter
    [ "Recovery"
    ; "Affected panes"
    ; "Snapshots"
    ; "Automation"
    ; "Autonomous cleanup"
    ; "Recovery safety"
    ]
    ~f:(fun label -> [%test_eq: int] (column label) (column "development"));
  [%test_eq: int] (column "▸ Affected panes") (column "▸ development")
;;

let%test_unit "affected panes expands into individually selectable scrollable warnings" =
  let handle = affected_handle Fixture.many_warnings_app in
  let rendered () = Handle.show_into_string handle in
  let collapsed = rendered () in
  assert (String.is_substring collapsed ~substring:"▸ Affected panes  [30]");
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
    assert (not (String.is_substring contents ~substring:"PREVIEW"));
    send handle Enter;
    [%test_eq: string] (rendered ()) contents;
    if index < 30 then send handle (Arrow `Down)
  done;
  send handle (Arrow `Down);
  assert (String.is_substring (rendered ()) ~substring:"Native history:");
  send handle (Arrow `Up);
  assert (String.is_substring (rendered ()) ~substring:"Pane: %30");
  resize handle 40 14;
  send handle Tab;
  for _ = 1 to 30 do
    send handle (Arrow `Down)
  done;
  assert (String.is_substring (rendered ()) ~substring:"will not resume.");
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

let%test_unit "refresh retains surviving panes and returns recovered selections to the \
               list"
  =
  let _, recovery, snapshots, services = Fixture.many_warnings_data in
  let recovery = Or_error.ok_exn recovery in
  let make refreshed =
    let handle =
      affected_handle
        (Fixture.make_app_with_reload
           ~initial_data:Fixture.many_warnings_data
           ~reload:(fun () ->
             Effect.return
               ( Or_error.error_string "fixture workspace"
               , Ok refreshed
               , snapshots
               , services ))
           ())
    in
    send handle Enter;
    send handle (Arrow `Down);
    handle
  in
  let recovered_first =
    { recovery with
      decisions =
        List.map recovery.decisions ~f:(fun decision ->
          if String.equal decision.Recovery.pane_id "%1"
          then { decision with action = Restart }
          else decision)
    }
  in
  let surviving = make recovered_first in
  send surviving (Arrow `Down);
  send surviving (ASCII 'r');
  assert (String.is_substring (Handle.show_into_string surviving) ~substring:"Pane: %2");
  let recovered = make recovered_first in
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
  let empty = make all_recovered in
  send empty (ASCII 'r');
  let contents = Handle.show_into_string empty in
  assert (String.is_substring contents ~substring:"Affected panes (0)");
  assert (
    String.is_substring contents ~substring:"No applications require shell-only recovery.");
  assert (not (String.is_substring contents ~substring:"▸ Affected panes"));
  send empty Enter;
  [%test_eq: string] (Handle.show_into_string empty) contents;
  ()
;;
