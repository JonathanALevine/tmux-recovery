open! Core
open Async
open Bonsai_term
module Handle = Bonsai_test.Handle
module Fixture = Tmux_recovery_tui_fixture.Tui_fixture

(** Issue #3: spamming refresh (the [r] key) used to launch an unbounded number of
    concurrent reloads, which corrupted the C heap (glibc "unaligned tcache chunk") on
    the multidomain runtime and crashed with SIGSEGV. The fix coalesces refreshes so that
    at most one reload is in flight at a time.

    This test drives the real TUI with an injected [reload] that records how many reloads
    run and the maximum number that overlap. It then spams the [r] key and asserts that
    only a single reload was ever started and that none ever overlapped. *)
let spam_refresh_is_coalesced () =
  let invocations = ref 0 in
  let in_flight = ref 0 in
  let max_in_flight = ref 0 in
  let release = Ivar.create () in
  let reload () =
    Effect.of_deferred_thunk (fun () ->
      let open Deferred.Let_syntax in
      invocations := !invocations + 1;
      in_flight := !in_flight + 1;
      max_in_flight := Int.max !max_in_flight !in_flight;
      (* Stay in flight until the test releases us, so that any (buggy) concurrent
         refresh would overlap with this one. *)
      let%bind () = Ivar.read release in
      in_flight := !in_flight - 1;
      let unavailable = Error.of_string "refresh regression test" in
      return
        (Error unavailable, Error unavailable, Error unavailable, Error unavailable))
  in
  let handle = Bonsai_term_test.create_handle (Fixture.make_app_with_reload ~reload) in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 22 };
  Handle.recompute_view handle;
  for _ = 1 to 50 do
    Bonsai_term_test.send_event handle (Key_press { key = ASCII 'r'; mods = [] });
    Handle.recompute_view handle
  done;
  Ivar.fill_exn release ();
  [%test_eq: int] !invocations 1;
  [%test_eq: int] !max_in_flight 1
;;

let%test_unit "spamming refresh is coalesced to a single in-flight reload" =
  spam_refresh_is_coalesced ()
;;
