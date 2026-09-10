# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Action commands execute directly. Remove `--dry-run`, `--approve`, and prune's
  `--apply` flag from scripts; plain `snapshots prune` now applies retention while
  preserving protected recovery points.
- Autonomous cleanup supports off/live modes and defaults to off. Legacy dry-run
  policies migrate to off with pending work cleared; historical simulated events
  remain distinguishable from actual closures. Explicit live/off and paused
  settings are preserved.
- Enter expands/collapses tree branches. Details follow selection automatically;
  Tab switches focus to scroll the read-only detail viewer with up/down and
  Home/End. A ◀ arrow marks focus while panel heading colors remain unchanged.
  Left/right, Shift-Tab, and Page Up/Down are unbound. Narrow terminals
  show navigation above details. Status groups recovery warnings in an Affected
  panes section with each application's location, cause, and recovery result.
- Bare `tmux-recovery` opens the TUI; remove the redundant `ui` command and the
  one-time `migrate` command family. Existing migration backup data is retained.
- Remove `scripts/check-version.sh`. The release workflow checks the built
  executables' exact versions directly, with no new dependencies.

### Fixed

- Match the `+built-...` version suffix in release checks instead of requiring a
  dot after the release version. Both packaged executables must match.
- Restore into a running tmux server with zero sessions after verifying its empty
  session inventory; continue to reject occupied or unobservable targets.
- Recover current interactive Codex conversations from their writer locks, keep
  moved working directories, reject child-agent references, and avoid guessing
  conversations from directory recency. Exited Codex-named shells no longer
  prevent good snapshots from advancing.
- Preserve process, writer-lock, and database failures as observation errors.
  Failed observations cannot replace a good snapshot or advance cleanup; pending
  cleanup is cancelled and must accumulate persistence and grace again.
- Autonomous cleanup requires every pane in the target window to be positively
  exited according to tmux and unrecoverable. Live and recoverable sibling panes
  protect the entire window, including during both fire-time checks.
- Run the real-tmux integration test using the configured tmux executable on
  macOS and Linux, propagate command errors, and fail on timeout.

## [0.3.0] - 2026-01-01

### Added

- **Autonomous cleanup** of idle, unrecoverable tmux windows (issue #9). A
  window that is blocked (an agent process with no durable thread to resume)
  and stays quiescent is now cleaned up automatically, without pressing `r`:
  - `observed -> persisted candidate -> visible grace countdown -> fresh
    eligibility recheck -> native snapshot -> second recheck -> close`.
  - The pipeline runs headless (no TUI required) via `autonomy tick` and a
    service timer (systemd `.timer` / launchd interval), and its state survives
    runner/TUI restarts through disk persistence under the XDG state dir.
  - **Dry-run is the default.** In dry-run the close is recorded in the audit
    log instead of performed. Live mode requires an explicit `--approve`.
  - New CLI subcommands: `autonomy status`, `autonomy tick`, `autonomy
    configure`, `autonomy cancel`, `autonomy pause`, `autonomy resume`.
  - The TUI shows the persisted autonomy policy, pending actions, the funnel,
    and the audit log, with `c` (cancel) and `p` (pause/resume) controls.
- A persistent autonomy store (atomic writes, `flock`, fail-closed on corrupt
  state, sequence-deduplicated append-only audit log) reusing the native
  snapshot adapter's atomic-write + lock discipline (no PID files, no nested
  self-locking).
- A durable audit log recording every scheduling, fire, cancel, abort, and
  failure, retained after an action leaves the active set.

### Changed

- The TUI displays only the persisted policy; the CLI `--autonomy-*` flags no
  longer override it.
- The tmux adapter gains `viewed_window_ids`, `activity_signature`,
  `server_identity`, and `digest_lines` to support eligibility rechecks.
- Service management recognizes the autonomy timer as a managed unit.

[Unreleased]: https://github.com/JonathanALevine/tmux-recovery/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/JonathanALevine/tmux-recovery/releases/tag/v0.3.0
