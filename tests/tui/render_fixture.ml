open! Core
open Bonsai_test

let show handle =
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  Handle.show handle
;;

let move_down handle count =
  List.init count ~f:Fn.id
  |> List.iter ~f:(fun _ ->
    Bonsai_term_test.send_event handle (Key_press { key = Arrow `Down; mods = [] }))
;;

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
  Handle.show moved;
  print_endline "--- WINDOW SELECTED ---";
  let window = Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  Bonsai_term_test.set_dimensions window { width = 100; height = 22 };
  Handle.recompute_view_until_stable window;
  move_down window 2;
  Bonsai_term_test.send_event window (Key_press { key = Arrow `Right; mods = [] });
  Bonsai_term_test.send_event window (Key_press { key = Arrow `Down; mods = [] });
  Handle.recompute_view_until_stable window;
  Handle.show window;
  print_endline "--- PANE SELECTED ---";
  let selected =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app
  in
  Bonsai_term_test.set_dimensions selected { width = 100; height = 22 };
  Handle.recompute_view_until_stable selected;
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Right; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Right; mods = [] });
  Handle.recompute_view_until_stable selected;
  Bonsai_term_test.send_event selected (Key_press { key = Arrow `Down; mods = [] });
  Handle.recompute_view_until_stable selected;
  Handle.show selected;
  print_endline "--- STATUS ---";
  let status = Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.app in
  Bonsai_term_test.set_dimensions status { width = 100; height = 22 };
  Handle.recompute_view_until_stable status;
  move_down status 3;
  Handle.show status;
  print_endline "--- STATUS WITH APPLICATION WARNING ---";
  let warning =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.warning_app
  in
  Bonsai_term_test.set_dimensions warning { width = 100; height = 22 };
  Handle.recompute_view_until_stable warning;
  move_down warning 3;
  Handle.show warning;
  print_endline "--- EMPTY STATUS ---";
  let empty =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.empty_app
  in
  Bonsai_term_test.set_dimensions empty { width = 100; height = 22 };
  Handle.recompute_view_until_stable empty;
  move_down empty 3;
  Handle.show empty;
  print_endline "--- UNAVAILABLE STATUS ---";
  let unavailable =
    Bonsai_term_test.create_handle Tmux_recovery_tui_fixture.Tui_fixture.unavailable_app
  in
  Bonsai_term_test.set_dimensions unavailable { width = 100; height = 22 };
  Handle.recompute_view_until_stable unavailable;
  move_down unavailable 3;
  Handle.show unavailable
;;
