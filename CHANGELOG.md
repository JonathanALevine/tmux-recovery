# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
