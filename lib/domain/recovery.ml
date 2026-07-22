open! Core

module Action = struct
  module T = struct
    type t =
      | Shell_fallback
      | Restart
      | Restart_clean
      | Resume
      | Blocked
    [@@deriving compare, equal, sexp_of]
  end

  include T
  include Comparable.Make_plain (T)

  let label = function
    | Shell_fallback -> "shell"
    | Restart -> "restart"
    | Restart_clean -> "restart-clean"
    | Resume -> "resume"
    | Blocked -> "blocked"
  ;;
end

module Codex_resume = struct
  type t =
    { thread_id : string
    ; cwd : string
    ; bypass_approvals : bool
    }
  [@@deriving equal, sexp_of]

  let is_hex = function
    | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
    | _ -> false
  ;;

  let valid_thread_id value =
    String.length value = 36
    && List.for_all [ 8; 13; 18; 23 ] ~f:(fun index -> Char.equal value.[index] '-')
    && String.for_alli value ~f:(fun index character ->
      if List.mem [ 8; 13; 18; 23 ] index ~equal:Int.equal
      then Char.equal character '-'
      else is_hex character)
  ;;

  let create ~thread_id ~cwd ~bypass_approvals =
    if not (valid_thread_id thread_id)
    then Or_error.error_s [%message "invalid Codex thread ID" thread_id]
    else if String.is_empty (String.strip cwd)
    then Or_error.error_string "Codex resume working directory is empty"
    else Ok { thread_id; cwd; bypass_approvals }
  ;;

  let to_yojson t =
    `Assoc
      [ "thread_id", `String t.thread_id
      ; "cwd", `String t.cwd
      ; "bypass_approvals", `Bool t.bypass_approvals
      ]
  ;;

  let of_yojson json =
    Or_error.try_with (fun () ->
      let open Yojson.Safe.Util in
      create
        ~thread_id:(member "thread_id" json |> to_string)
        ~cwd:(member "cwd" json |> to_string)
        ~bypass_approvals:(member "bypass_approvals" json |> to_bool)
      |> Or_error.ok_exn)
  ;;
end

type decision =
  { pane_id : string
  ; observed : string
  ; action : Action.t
  ; executable : string option
  ; argv : string list
  ; fidelity : string
  ; reason : string
  ; rule_id : string option
  }
[@@deriving equal, sexp_of]

type plan =
  { source : Workspace.Source.t
  ; decisions : decision list
  ; warnings : string list
  }
[@@deriving equal, sexp_of]

let basename command = command |> String.strip |> String.lowercase |> Filename.basename

let fixed (pane : Workspace.Pane.t) action executable fidelity reason =
  { pane_id = pane.Workspace.Pane.id
  ; observed = pane.current_command
  ; action
  ; executable = Some executable
  ; argv = []
  ; fidelity
  ; reason
  ; rule_id = Some ("builtin:" ^ executable)
  }
;;

let classify ?codex_resume ?(codex_detected = false) (pane : Workspace.Pane.t) =
  let command = basename pane.current_command in
  match codex_resume, codex_detected, command with
  | Some (resume : Codex_resume.t), _, _ ->
    { pane_id = pane.id
    ; observed = pane.current_command
    ; action = Resume
    ; executable = Some "codex"
    ; argv =
        ([ "resume"; "-C"; resume.cwd; resume.thread_id ]
         @
         if resume.bypass_approvals
         then [ "--dangerously-bypass-approvals-and-sandbox" ]
         else [])
    ; fidelity = "same Codex conversation"
    ; reason = "captured a validated Codex thread reference"
    ; rule_id = Some "adapter:codex:v1"
    }
  | None, true, _ ->
    { pane_id = pane.id
    ; observed = pane.current_command
    ; action = Blocked
    ; executable = None
    ; argv = []
    ; fidelity = "shell fallback"
    ; reason = "Codex is running, but no durable thread reference is available"
    ; rule_id = Some "adapter:codex:missing-thread"
    }
  | None, false, ("" | "sh" | "bash" | "zsh" | "fish" | "dash") ->
    { pane_id = pane.id
    ; observed = pane.current_command
    ; action = Shell_fallback
    ; executable = None
    ; argv = []
    ; fidelity = "layout and working directory"
    ; reason = "pane is already at an interactive shell"
    ; rule_id = None
    }
  | None, false, (("htop" | "btop" | "top") as executable) ->
    fixed
      pane
      Restart
      executable
      "new application instance"
      "matched the conservative built-in restart catalog"
  | None, false, "tmux-recovery" ->
    fixed
      pane
      Restart
      "tmux-recovery"
      "new interactive recovery navigator"
      "matched the native self-recovery rule"
  | None, false, (("python" | "python3" | "ipython") as executable) ->
    fixed
      pane
      Restart_clean
      executable
      "clean interpreter; no in-memory variables"
      "only a fixed bare interpreter command will be launched"
  | None, false, "codex" ->
    { pane_id = pane.id
    ; observed = pane.current_command
    ; action = Blocked
    ; executable = None
    ; argv = []
    ; fidelity = "shell fallback"
    ; reason = "no durable Codex thread reference was captured for this pane"
    ; rule_id = Some "adapter:codex:missing-thread"
    }
  | None, false, executable ->
    { pane_id = pane.id
    ; observed = pane.current_command
    ; action = Shell_fallback
    ; executable = None
    ; argv = []
    ; fidelity = "layout and working directory"
    ; reason = [%string "no approved recovery rule for %{executable}"]
    ; rule_id = None
    }
;;

let plan
  ?(codex_resumes = String.Map.empty)
  ?(codex_detected = String.Set.empty)
  workspace
  =
  let panes =
    Workspace.ordered_sessions workspace
    |> List.concat_map ~f:(fun session ->
      Workspace.links_for_session workspace ~session_id:session.id)
    |> List.concat_map ~f:(fun link ->
      Workspace.panes_for_window workspace ~window_id:link.window_id)
    |> List.fold ~init:String.Map.empty ~f:(fun panes pane ->
      Map.set panes ~key:pane.id ~data:pane)
    |> Map.data
  in
  let decisions =
    List.map panes ~f:(fun pane ->
      classify
        ?codex_resume:(Map.find codex_resumes pane.Workspace.Pane.id)
        ~codex_detected:(Set.mem codex_detected pane.id)
        pane)
  in
  let warnings =
    if List.exists decisions ~f:(fun decision -> Action.equal decision.action Blocked)
    then
      [ "one or more applications require an adapter or explicit rule; their panes will \
         remain usable shells"
      ]
    else []
  in
  { source = workspace.source; decisions; warnings }
;;

let counts plan =
  List.fold plan.decisions ~init:Action.Map.empty ~f:(fun counts decision ->
    Map.update counts decision.action ~f:(function
      | None -> 1
      | Some count -> count + 1))
  |> Map.to_alist
;;

let to_yojson plan =
  let decisions =
    List.map plan.decisions ~f:(fun decision ->
      `Assoc
        [ "pane_id", `String decision.pane_id
        ; "observed", `String decision.observed
        ; "action", `String (Action.label decision.action)
        ; ( "executable"
          , Option.value_map decision.executable ~default:`Null ~f:(fun value ->
              `String value) )
        ; "argv", `List (List.map decision.argv ~f:(fun value -> `String value))
        ; "fidelity", `String decision.fidelity
        ; "reason", `String decision.reason
        ; ( "rule_id"
          , Option.value_map decision.rule_id ~default:`Null ~f:(fun value ->
              `String value) )
        ])
  in
  `Assoc
    [ "source", `String (Workspace.Source.label plan.source)
    ; "decisions", `List decisions
    ; "warnings", `List (List.map plan.warnings ~f:(fun warning -> `String warning))
    ]
;;
