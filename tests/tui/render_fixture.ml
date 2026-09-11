open! Core
open Bonsai_test

let show_view handle = Handle.show_into_string handle |> String.rstrip |> print_endline

let show handle =
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  show_view handle
;;

let move handle direction count =
  List.init count ~f:Fn.id
  |> List.iter ~f:(fun _ ->
    Bonsai_term_test.send_event handle (Key_press { key = Arrow direction; mods = [] }))
;;

let move_down handle count = move handle `Down count

let () =
  let initial =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app
  in
  show initial;
  print_endline "--- MOVED ---";
  let moved = Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  Bonsai_term_test.set_dimensions moved { width = 100; height = 22 };
  Handle.recompute_view moved;
  Bonsai_term_test.send_event moved (Key_press { key = Arrow `Down; mods = [] });
  show_view moved;
  print_endline "--- WINDOW SELECTED ---";
  let window = Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  Bonsai_term_test.set_dimensions window { width = 100; height = 22 };
  Handle.recompute_view_until_stable window;
  move_down window 2;
  Bonsai_term_test.send_event window (Key_press { key = Enter; mods = [] });
  Bonsai_term_test.send_event window (Key_press { key = Arrow `Down; mods = [] });
  Handle.recompute_view_until_stable window;
  show_view window;
  print_endline "--- PANE SELECTED ---";
  let selected =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app
  in
  Bonsai_term_test.set_dimensions selected { width = 100; height = 22 };
  Handle.recompute_view_until_stable selected;
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Enter; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Enter; mods = [] });
  Handle.recompute_view_until_stable selected;
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Handle.recompute_view_until_stable selected;
  show_view selected;
  print_endline "--- NARROW PANE ---";
  Bonsai_term_test.set_dimensions selected { width = 60; height = 22 };
  show_view selected;
  print_endline "--- SHORT NARROW PANE ---";
  Bonsai_term_test.set_dimensions selected { width = 40; height = 14 };
  show_view selected;
  print_endline "--- RESIZED WIDE AGAIN ---";
  show selected;
  let status_handle app =
    let handle = Bonsai_term_test.create_handle app in
    Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
    Handle.recompute_view_until_stable handle;
    move_down handle 3;
    Handle.recompute_view_until_stable handle;
    handle
  in
  print_endline "--- STATUS ---";
  let status = status_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  show_view status;
  Bonsai_term_test.send_event status (Key_press { key = Enter; mods = [] });
  print_endline "--- STATUS COLLAPSED ---";
  show_view status;
  let warning = status_handle Tmux_recovery_tui_fixture.Tui_fixture.warning_app in
  print_endline "--- STATUS WITH APPLICATION WARNING ---";
  show_view warning;
  List.iter
    [ "RECOVERY"
    ; "AFFECTED PANES"
    ; "SNAPSHOTS"
    ; "AUTOMATION"
    ; "AUTONOMOUS CLEANUP"
    ; "RECOVERY SAFETY"
    ]
    ~f:(fun label ->
      move_down warning 1;
      print_endline ("--- " ^ label ^ " SECTION ---");
      show_view warning);
  let affected = status_handle Tmux_recovery_tui_fixture.Tui_fixture.many_warnings_app in
  move_down affected 2;
  Bonsai_term_test.send_event affected (Key_press { key = Tab; mods = [] });
  print_endline "--- FOCUSED AFFECTED PANES DETAILS ---";
  show_view affected;
  move_down affected 400;
  print_endline "--- AFFECTED PANES SCROLLED TO END ---";
  show_view affected;
  Bonsai_term_test.set_dimensions affected { width = 40; height = 14 };
  Handle.recompute_view_until_stable affected;
  move affected `Up 400;
  print_endline "--- NARROW AFFECTED PANES ---";
  show_view affected;
  List.iter
    [ "EMPTY", Tmux_recovery_tui_fixture.Tui_fixture.empty_app
    ; "UNAVAILABLE", Tmux_recovery_tui_fixture.Tui_fixture.unavailable_app
    ]
    ~f:(fun (label, app) ->
      let handle = status_handle app in
      print_endline ("--- " ^ label ^ " STATUS ---");
      show_view handle;
      move_down handle 3;
      print_endline ("--- " ^ label ^ " SNAPSHOTS ---");
      show_view handle;
      move_down handle 1;
      print_endline ("--- " ^ label ^ " AUTOMATION ---");
      show_view handle)
;;
