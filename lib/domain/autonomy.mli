open! Core

(** Autonomous cleanup of idle, unrecoverable windows.

    Pure engine: all wall-clock time and all side effects (snapshotting, closing a
    window, file access) are injected by the caller. No filesystem, tmux, Async, or
    TUI dependencies live here.

    Safety model: a window is a candidate only while it is (a) unrecoverable (a
    [Recovery.Blocked] decision in the window), (b) not viewed by any tmux client
    (the exact window, not merely its containing session), and (c) quiescent
    (repeated unchanged activity observations). A candidate fully eligible
    continuously for the persistence threshold is scheduled as an action with a
    unique ID and a grace deadline. The application runner drives firing: full
    fire-time recheck, fresh native snapshot, second recheck, then close of the exact
    window. In [Dry_run] the fire is recorded durably and nothing is executed.

    Re-arming: after any terminal outcome (fired, cancelled, aborted, failed) the
    window is suppressed until it leaves the funnel and re-enters it. Pausing cancels
    pending deadlines and clears the funnel, so resuming always starts a fresh
    persistence period and never fires an overdue action immediately. Mode or
    threshold changes safely reset every eligibility cycle. *)

module Mode : sig
  type t =
    | Off
    | Dry_run
    | Live
  [@@deriving compare, equal, sexp_of]

  val label : t -> string
  val of_string : string -> t Or_error.t
end

type config =
  { mode : Mode.t
  ; grace_seconds : int
  ; persistence_seconds : int
  ; snapshot_before_fire : bool
  }
[@@deriving compare, equal, sexp_of]

(** Dry-run is the default: nothing is ever executed until live mode is explicitly
    configured. *)
val default_config : config

(** Fingerprint of a target window, bound to a tmux server identity so a reused
    [@id] after a server restart cannot be mistaken for the original target. *)
type target =
  { window_id : string
  ; session_id : string
  ; server_identity : string
  ; window_name : string
  ; window_layout : string
  ; panes : (string * string) list
  (** Sorted list of (pane_id, current_command) for the window. *)
  }
[@@deriving compare, equal, sexp_of]

(** One candidate window observed during a single tick: blocked, unviewed, carrying
    its target fingerprint and the activity signature sampled for this tick. *)
type candidate =
  { target : target
  ; reason : string
  ; signature : string
  }
[@@deriving compare, equal, sexp_of]

type outcome =
  | Scheduled
  | Fired
      of { at : Time_ns.t; snapshot_id : string option; note : string; dry_run : bool }
  | Cancelled of { at : Time_ns.t; reason : string }
  | Aborted of { at : Time_ns.t; reason : string }
  | Failed of { at : Time_ns.t; reason : string }
[@@deriving compare, equal, sexp_of]

(** A unique action ID (never the window ID) identifies one scheduling of one window.
    The same window may be scheduled again in a later eligibility cycle. *)
type action =
  { id : string
  ; window_id : string
  ; reason : string
  ; target : target
  ; scheduled_at : Time_ns.t
  ; deadline : Time_ns.t
  ; outcome : outcome
  }
[@@deriving compare, equal, sexp_of]

module Audit_event : sig
  type t =
    | Scheduled
    | Fired
    | Cancelled
    | Aborted
    | Failed
    | Paused
    | Resumed
    | Policy_changed
  [@@deriving compare, equal, sexp_of]
end

type audit_entry =
  { at : Time_ns.t
  ; event : Audit_event.t
  ; action_id : string option
  ; window_id : string option
  ; detail : string
  }
[@@deriving compare, equal, sexp_of]

(** Per-window eligibility bookkeeping inside the current cycle. *)
type candidate_state =
  { eligibility_since : Time_ns.t option
  (** Start of the current continuous fully-eligible (quiescent) run, if any. *)
  ; last_signature : string option
  ; suppressed : bool
  (** True once an action in this cycle reached a terminal outcome; cleared only
      when the window leaves the funnel. *)
  }
[@@deriving compare, equal, sexp_of]

type state =
  { config : config
  ; paused : bool
  ; paused_at : Time_ns.t option
  ; next_action_id : int
  ; candidates : candidate_state String.Map.t
  ; active : action list
  (** Actions still [Scheduled]. *)
  ; archived : action list
  (** Terminal actions, newest first. *)
  ; audit : audit_entry list
  (** Newest first, capped. The durable audit log is the adapter's append-only file. *)
  }
[@@deriving compare, equal, sexp_of]

val empty : config:config -> state
val paused : state -> bool

(** [detect ~workspace ~recovery ~viewed] returns (window_id, session_id, reason)
    for every window with at least one [Recovery.Blocked] decision that is not
    currently viewed by a tmux client. [viewed] holds the exact window IDs clients
    are looking at (from [tmux list-clients]); a window in an attached session is
    still a candidate when no client views that exact window. *)
val detect
  :  workspace:Workspace.t
  -> recovery:Recovery.plan
  -> viewed:string list
  -> (string * string * string) list

(** Advance the engine by one tick using the candidates observed now.

    - A window that is no longer a candidate leaves the funnel; its pending action,
      if any, is auto-cancelled and its cycle is reset.
    - The first activity sample of a window is never quiescent; an unchanged second
      sample starts (or resumes) the eligibility clock; any signature change resets
      it.
    - A fully eligible candidate whose eligibility has persisted for
      [config.persistence_seconds] is scheduled with a unique action ID and a
      deadline [config.grace_seconds] in the future, unless suppressed or already
      scheduled in this cycle.
    - A pending action whose window is still a candidate but is no longer quiescent
      is auto-cancelled.

    While paused, or in [Off] mode, [tick] changes nothing. *)
val tick : now:Time_ns.t -> candidates:candidate list -> state -> state

val active : state -> action list
val due : now:Time_ns.t -> state -> action list
val remaining : now:Time_ns.t -> action -> Time_ns.Span.t
val find_action : state -> id:string -> action option
val latest_action_for_window : state -> window_id:string -> action option
val last_signature : state -> window_id:string -> string option

(** [candidates] reports the current funnel for display: window ID, continuous
    eligibility start (if any), and whether the window is suppressed. *)
val candidates : state -> (string * Time_ns.t option * bool) list

(** [target_matches action fresh] succeeds only when the freshly observed candidate
    belongs to the same server and the same window/pane fingerprint as the target
    recorded when the action was scheduled. *)
val target_matches : action -> candidate -> unit Or_error.t

(** Record terminal transitions. Each transition archives the action, appends an
    audit entry, and suppresses the window for the current eligibility cycle. *)
val apply_fire
  :  now:Time_ns.t
  -> id:string
  -> ?snapshot_id:string
  -> dry_run:bool
  -> note:string
  -> state
  -> state

val abort_fire : now:Time_ns.t -> id:string -> reason:string -> state -> state
val fail_fire : now:Time_ns.t -> id:string -> reason:string -> state -> state

(** User cancellation of one explicit action ID. Cancelling an unknown or already
    terminal action ID is a no-op. *)
val cancel : now:Time_ns.t -> id:string -> ?reason:string -> state -> state

(** Global pause: cancels every pending deadline, clears the funnel, and records the
    transition. No ticks accumulate eligibility while paused. *)
val pause : now:Time_ns.t -> state -> state

(** Resume: requires a fresh persistence period and grace countdown (the funnel was
    cleared on pause, so no overdue action can fire immediately). *)
val resume : now:Time_ns.t -> state -> state

(** Adopt a new policy. Any change cancels pending actions, clears the funnel, and
    records the change; an identical config leaves the state untouched. *)
val with_config : now:Time_ns.t -> config -> state -> state

val audit : state -> audit_entry list
val audit_lines : state -> string list

val config_to_yojson : config -> Yojson.Safe.t
val config_of_yojson : Yojson.Safe.t -> config Or_error.t
val state_to_yojson : state -> Yojson.Safe.t
val state_of_yojson : Yojson.Safe.t -> state Or_error.t
val audit_entry_to_yojson : audit_entry -> Yojson.Safe.t
val audit_entry_of_yojson : Yojson.Safe.t -> audit_entry Or_error.t
