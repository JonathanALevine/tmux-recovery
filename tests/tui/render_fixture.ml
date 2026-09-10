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
  print_endline "--- STATUS ---";
  let status = Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  Bonsai_term_test.set_dimensions status { width = 100; height = 22 };
  Handle.recompute_view_until_stable status;
  move_down status 3;
  show_view status;
  print_endline "--- STATUS WITH APPLICATION WARNING ---";
  let warning =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.warning_app
  in
  Bonsai_term_test.set_dimensions warning { width = 100; height = 22 };
  Handle.recompute_view_until_stable warning;
  move_down warning 3;
  show_view warning;
  let affected =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.warning_app
  in
  Bonsai_term_test.set_dimensions affected { width = 100; height = 22 };
  Handle.recompute_view_until_stable affected;
  move_down affected 3;
  Bonsai_term_test.send_event affected (Key_press { key = Tab; mods = [] });
  Bonsai_term_test.send_event affected (Key_press { key = Enter; mods = [] });
  print_endline "--- AFFECTED PANES COLLAPSED IN STATUS ---";
  show_view affected;
  Bonsai_term_test.send_event affected (Key_press { key = Enter; mods = [] });
  print_endline "--- AFFECTED PANES EXPANDED IN STATUS ---";
  show_view affected;
  Bonsai_term_test.set_dimensions affected { width = 40; height = 14 };
  Handle.recompute_view_until_stable affected;
  Bonsai_term_test.send_event affected (Key_press { key = Enter; mods = [] });
  print_endline "--- NARROW AFFECTED PANES COLLAPSED ---";
  show_view affected;
  Bonsai_term_test.send_event affected (Key_press { key = Enter; mods = [] });
  print_endline "--- NARROW AFFECTED PANES EXPANDED ---";
  show_view affected;
  print_endline "--- FOCUSED STATUS DETAILS ---";
  Bonsai_term_test.send_event warning (Key_press { key = Tab; mods = [] });
  show_view warning;
  print_endline "--- STATUS SCROLLED TO END ---";
  move_down warning 100;
  show_view warning;
  print_endline "--- NARROW STATUS ---";
  Bonsai_term_test.set_dimensions warning { width = 40; height = 14 };
  Handle.recompute_view_until_stable warning;
  move warning `Up 100;
  move_down warning 10;
  show_view warning;
  print_endline "--- EMPTY STATUS ---";
  let empty =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.empty_app
  in
  Bonsai_term_test.set_dimensions empty { width = 100; height = 22 };
  Handle.recompute_view_until_stable empty;
  move_down empty 3;
  show_view empty;
  print_endline "--- UNAVAILABLE STATUS ---";
  let unavailable =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.unavailable_app
  in
  Bonsai_term_test.set_dimensions unavailable { width = 100; height = 22 };
  Handle.recompute_view_until_stable unavailable;
  move_down unavailable 3;
  show_view unavailable
;;
