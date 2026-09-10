  $ ./render_fixture.exe
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL                                              │
  │  Overview                                  │tmux-recovery                                          │
  │▾ Sessions  [online]                        │A conservative recovery control plane for tmux.        │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [ready]                           │tmux: online                                           │
  │                                            │Sessions: 1                                            │
  │                                            │Canonical windows: 1                                   │
  │                                            │Panes: 1                                               │
  │                                            │Native snapshots: 1 saved · rolling limit 10           │
  │                                            │                                                       │
  │                                            │Use snapshot to save and restore to recover your       │
  │                                            │workspace.                                             │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- MOVED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL                                              │
  │  Overview                                  │Sessions                                               │
  │▾ Sessions  [online]                        │Source: live                                           │
  │  ▸ development  [attached]                 │Server: running                                        │
  │  Status  [ready]                           │Version: tmux test                                     │
  │                                            │Socket: default                                        │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- WINDOW SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   PREVIEW                                             │
  │  Overview                                  │monitoring                                             │
  │▾ Sessions  [online]                        │Window 0 · active pane 0 · btop                        │
  │  ▾ development  [attached]                 │                                                       │
  │    ▸ 0:monitoring  [active]                │Live window contents                                   │
  │  Status  [ready]                           │Active pane · bottom of screen · read-only · refresh wi│
  │                                            │                                                       │
  │                                            │older output 01                                        │
  │                                            │older output 02                                        │
  │                                            │older output 03                                        │
  │                                            │older output 04                                        │
  │                                            │older output 05                                        │
  │                                            │older output 06                                        │
  │                                            │older output 07                                        │
  │                                            │older output 08                                        │
  │                                            │older output 09                                        │
  │                                            │older output 10                                        │
  │                                            │older output 11                                        │
  │                                            │older output 12                                        │
  │                                            │$ printf 'latest pane output\n'                        │
  │                                            │latest btop output                                     │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- PANE SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   PREVIEW                                             │
  │  Overview                                  │Pane 0                                                 │
  │▾ Sessions  [online]                        │Typed ID: %1                                           │
  │  ▾ development  [attached]                 │Working directory: /Users/demo                         │
  │    ▾ 0:monitoring  [active]                │Title: btop                                            │
  │      ▸ pane 0  [active]                    │Observed command: btop                                 │
  │  Status  [ready]                           │Recovery: restart                                      │
  │                                            │                                                       │
  │                                            │Latest pane output                                     │
  │                                            │Bottom of pane · read-only · refresh with r            │
  │                                            │                                                       │
  │                                            │older output 05                                        │
  │                                            │older output 06                                        │
  │                                            │older output 07                                        │
  │                                            │older output 08                                        │
  │                                            │older output 09                                        │
  │                                            │older output 10                                        │
  │                                            │older output 11                                        │
  │                                            │older output 12                                        │
  │                                            │$ printf 'latest pane output\n'                        │
  │                                            │latest btop output                                     │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW PANE ---
  ┌────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                                               │
  │▾ Sessions  [online]                                        │
  │  ▾ development  [attached]                                 │
  │    ▾ 0:monitoring  [active]                                │
  │      ▸ pane 0  [active]                                    │
  │────────────────────────────────────────────────────────────│
  │   PREVIEW                                                  │
  │Pane 0                                                      │
  │Typed ID: %1                                                │
  │Working directory: /Users/demo                              │
  │Title: btop                                                 │
  │Observed command: btop                                      │
  │Recovery: restart                                           │
  │                                                            │
  │Latest pane output                                          │
  │Bottom of pane · read-only · refresh with r                 │
  │                                                            │
  │older output 11                                             │
  │older output 12                                             │
  │$ printf 'latest pane output\n'                             │
  │latest btop output                                          │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refre│
  └────────────────────────────────────────────────────────────┘
  --- SHORT NARROW PANE ---
  ┌────────────────────────────────────────┐
  │ ▶ NAVIGATION                           │
  │    ▾ 0:monitoring  [active]            │
  │      ▸ pane 0  [active]                │
  │────────────────────────────────────────│
  │   PREVIEW                              │
  │Pane 0 · btop                           │
  │Recovery: restart                       │
  │Latest pane output                      │
  │older output 10                         │
  │older output 11                         │
  │older output 12                         │
  │$ printf 'latest pane output\n'         │
  │latest btop output                      │
  │ Tab detail · ↑/↓ navigate · Enter expan│
  └────────────────────────────────────────┘
  --- RESIZED WIDE AGAIN ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   PREVIEW                                             │
  │  Overview                                  │Pane 0                                                 │
  │▾ Sessions  [online]                        │Typed ID: %1                                           │
  │  ▾ development  [attached]                 │Working directory: /Users/demo                         │
  │    ▾ 0:monitoring  [active]                │Title: btop                                            │
  │      ▸ pane 0  [active]                    │Observed command: btop                                 │
  │  Status  [ready]                           │Recovery: restart                                      │
  │                                            │                                                       │
  │                                            │Latest pane output                                     │
  │                                            │Bottom of pane · read-only · refresh with r            │
  │                                            │                                                       │
  │                                            │older output 05                                        │
  │                                            │older output 06                                        │
  │                                            │older output 07                                        │
  │                                            │older output 08                                        │
  │                                            │older output 09                                        │
  │                                            │older output 10                                        │
  │                                            │older output 11                                        │
  │                                            │older output 12                                        │
  │                                            │$ printf 'latest pane output\n'                        │
  │                                            │latest btop output                                     │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL · 1–20/54                                    │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [ready]                           │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │                                            │pane(s)                                                │
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe        │
  │                                            │restart(s) · 0 blocked                                 │
  │                                            │                                                       │
  │                                            │Affected panes (0)                                     │
  │                                            │No applications require shell-only recovery.           │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: PASS · valid native recovery point available│
  │                                            │Native history: 1 saved · rolling limit 10             │
  │                                            │Last good: 2026-07-21 01:32:39.000000000Z              │
  │                                            │Native storage: 8.0 KiB                                │
  │                                            │                                                       │
  │                                            │Automation                                             │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS WITH APPLICATION WARNING ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL · 1–20/58                                    │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │                                            │pane(s)                                                │
  │                                            │Applications: WARN · 1 shell fallback(s) · details     │
  │                                            │below                                                  │
  │                                            │                                                       │
  │                                            │Affected panes (1)                                     │
  │                                            │                                                       │
  │                                            │development:0.0 · %1                                   │
  │                                            │Application: codex                                     │
  │                                            │Cause: Codex has no durable thread ID.                 │
  │                                            │Recovery: shell only; the application will not resume. │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: PASS · valid native recovery point available│
  │                                            │Native history: 1 saved · rolling limit 10             │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- FOCUSED STATUS DETAILS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │   NAVIGATION                               │ ▶ DETAIL · 1–20/58                                    │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │                                            │pane(s)                                                │
  │                                            │Applications: WARN · 1 shell fallback(s) · details     │
  │                                            │below                                                  │
  │                                            │                                                       │
  │                                            │Affected panes (1)                                     │
  │                                            │                                                       │
  │                                            │development:0.0 · %1                                   │
  │                                            │Application: codex                                     │
  │                                            │Cause: Codex has no durable thread ID.                 │
  │                                            │Recovery: shell only; the application will not resume. │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: PASS · valid native recovery point available│
  │                                            │Native history: 1 saved · rolling limit 10             │
  │ Tab navigation · ↑/↓ scroll · Home/End · r refresh · q quit · c cancel · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS SCROLLED TO END ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │   NAVIGATION                               │ ▶ DETAIL · 39–58/58                                   │
  │  Overview                                  │tmux_recovery_1784597559000000000_0123abcd.snapshot    │
  │▾ Sessions  [online]                        │Runtime version: 0.3.0-dev.14                          │
  │  ▸ development  [attached]                 │Last result: launchctl exit status 0                   │
  │  Status  [attention]                       │                                                       │
  │                                            │Autonomous cleanup                                     │
  │                                            │Policy: off (no autonomous cleanup) · grace 1h 0m ·    │
  │                                            │candidate for ≥ 15m 0s · snapshot before               │
  │                                            │fire: yes                                              │
  │                                            │Pending actions: 0                                     │
  │                                            │No windows are currently scheduled for autonomous      │
  │                                            │close.                                                 │
  │                                            │                                                       │
  │                                            │Eligibility funnel: empty.                             │
  │                                            │No autonomous actions recorded yet.                    │
  │                                            │p pauses or resumes the pipeline.                      │
  │                                            │                                                       │
  │                                            │Recovery safety: Snapshot integrity and occupied       │
  │                                            │targets are checked.                                   │
  │                                            │Use the CLI for snapshot restore and automation        │
  │                                            │changes.                                               │
  │ Tab navigation · ↑/↓ scroll · Home/End · r refresh · q quit · c cancel · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW AFFECTED PANES ---
  ┌────────────────────────────────────────┐
  │   NAVIGATION                           │
  │  ▸ development  [attached]             │
  │  Status  [attention]                   │
  │────────────────────────────────────────│
  │ ▶ DETAIL · 11–18/68                    │
  │                                        │
  │Affected panes (1)                      │
  │                                        │
  │development:0.0 · %1                    │
  │Application: codex                      │
  │Cause: Codex has no durable thread ID.  │
  │Recovery: shell only; the application   │
  │will not resume.                        │
  │ Tab navigation · ↑/↓ scroll · Home/End │
  └────────────────────────────────────────┘
  --- EMPTY STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL · 1–20/46                                    │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │                                            │pane(s)                                                │
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe        │
  │                                            │restart(s) · 0 blocked                                 │
  │                                            │                                                       │
  │                                            │Affected panes (0)                                     │
  │                                            │No applications require shell-only recovery.           │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: WARN · no valid native recovery point;      │
  │                                            │reboot recovery is unsafe                              │
  │                                            │Native history: 0 saved · rolling limit 10             │
  │                                            │Last good: none                                        │
  │                                            │Native storage: 0 B                                    │
  │                                            │                                                       │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- UNAVAILABLE STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ ▶ NAVIGATION                               │   DETAIL · 1–20/40                                    │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │                                            │pane(s)                                                │
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe        │
  │                                            │restart(s) · 0 blocked                                 │
  │                                            │                                                       │
  │                                            │Affected panes (0)                                     │
  │                                            │No applications require shell-only recovery.           │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: WARN · snapshot inventory unavailable       │
  │                                            │fixture snapshot directory is unreadable               │
  │                                            │Press r to retry. Existing snapshot files are          │
  │                                            │unchanged.                                             │
  │                                            │                                                       │
  │                                            │Automation                                             │
  │ Tab detail · ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause        │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
