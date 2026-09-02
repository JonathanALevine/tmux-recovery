(** Durable storage for the autonomous cleanup pipeline: policy, engine
    state, and audit log under the XDG config/state directories, guarded by
    an advisory lock. See the implementation for the file layout. *)

open! Core
open Async

module Autonomy = Tmux_recovery_domain.Autonomy

type t

(** Create the store directories and return the store. [?config_home] and
    [?state_home] override the XDG config/state roots (tests use temp
    dirs). *)
val create : ?config_home:string -> ?state_home:string -> unit -> t Or_error.t

val policy_path : t -> string
val state_path : t -> string
val audit_path : t -> string
val lock_path : t -> string

(** The user's policy. Missing file means the default (dry-run) policy; a
    corrupt file is an error. *)
val load_policy : t -> Autonomy.config Or_error.t
val save_policy : t -> Autonomy.config -> unit Or_error.t

(** The engine state. Missing file means an empty state with the current
    policy. A corrupt or unreadable state file is an error (fail-closed):
    the engine must not run, and no window is ever closed. *)
val load_state : t -> Autonomy.state Or_error.t
val save_state : t -> Autonomy.state -> unit Or_error.t

(** Idempotently append audit entries that are not already in the durable
    log, taking the store's advisory lock. Safe to call repeatedly. Callers
    that already hold the lock must use [sync_audit_unlocked] instead. *)
val sync_audit : t -> Autonomy.audit_entry list -> unit Or_error.t

(** Like [sync_audit], but without taking the lock: the caller must already
    hold the store's advisory lock (inside [with_lock] or [with_lock_async]). *)
val sync_audit_unlocked : t -> Autonomy.audit_entry list -> unit Or_error.t

(** The durable audit log, newest first. Corrupt lines are skipped. *)
val read_audit : t -> Autonomy.audit_entry list Or_error.t

(** Run [f] while holding the store's advisory lock. The lock blocks until
    available and is released (and closed) even if [f] raises. *)
val with_lock : t -> f:(unit -> 'a Or_error.t) -> 'a Or_error.t

(** Like [with_lock], but for deferred computations: the lock is held until
    the returned deferred settles (resolves or raises), so asynchronous work
    (tmux observation, snapshots, window close) stays inside the transaction.
    The blocking acquire runs on the main thread, like [with_lock]. *)
val with_lock_async : t -> f:(unit -> 'a Deferred.t) -> 'a Deferred.t
