open! Core
open Async
module Domain_recovery = Tmux_recovery_domain.Recovery

type t =
  { tmux : Tmux_adapter.config
  ; codex : Codex.config
  }

let create ?socket_name ?codex () =
  { tmux = Tmux_adapter.default_config ?socket_name ()
  ; codex = Option.value codex ~default:(Codex.default_config ())
  }
;;

let workspace t = Tmux_adapter.observe t.tmux
let capture_pane t ~pane_id = Tmux_adapter.capture_pane t.tmux ~pane_id

let plan t =
  let%bind result = workspace t in
  match result with
  | Error _ as error -> return error
  | Ok workspace ->
    let%map capture = Codex.capture t.codex workspace in
    Ok
      (Domain_recovery.plan
         ~codex_resumes:capture.resumes
         ~codex_detected:capture.detected_panes
         workspace)
;;
