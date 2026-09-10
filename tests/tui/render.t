  $ ./render_fixture.exe
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
  │  Overview                                  │tmux-recovery                                          │
  │▾ Sessions  [online]                        │A conservative recovery control plane for tmux.        │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [ready]                           │tmux: online                                           │
  │                                            │Sessions: 1                                            │
  │                                            │Canonical windows: 1                                   │
  │                                            │Panes: 1                                               │
  │                                            │Native snapshots: 1 saved · rolling limit 10           │
  │                                            │                                                       │
  │                                            │Use snapshot to save and restore to recover your worksp│
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- MOVED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- WINDOW SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ PREVIEW                                               │
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- PANE SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ PREVIEW                                               │
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW PANE ---
  ┌────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                                 │
  │▾ Sessions  [online]                                        │
  │  ▾ development  [attached]                                 │
  │    ▾ 0:monitoring  [active]                                │
  │      ▸ pane 0  [active]                                    │
  │────────────────────────────────────────────────────────────│
  │ PREVIEW                                                    │
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit ·│
  └────────────────────────────────────────────────────────────┘
  --- SHORT NARROW PANE ---
  ┌────────────────────────────────────────┐
  │ NAVIGATION                             │
  │    ▾ 0:monitoring  [active]            │
  │      ▸ pane 0  [active]                │
  │────────────────────────────────────────│
  │ PREVIEW                                │
  │Pane 0 · btop                           │
  │Recovery: restart                       │
  │Latest pane output                      │
  │older output 10                         │
  │older output 11                         │
  │older output 12                         │
  │$ printf 'latest pane output\n'         │
  │latest btop output                      │
  │ ↑/↓ navigate · Enter expand/collapse · │
  └────────────────────────────────────────┘
  --- RESIZED WIDE AGAIN ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ PREVIEW                                               │
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
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [ready]                           │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1 pane(s│
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe restart│
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: PASS · valid native recovery point available│
  │                                            │Native history: 1 saved · rolling limit 10             │
  │                                            │Last good: 2026-07-21 01:32:39.000000000Z              │
  │                                            │Native storage: 8.0 KiB                                │
  │                                            │                                                       │
  │                                            │Automation                                             │
  │                                            │Readiness: PASS · tmux-recovery manages save and login │
  │                                            │Periodic save: PASS · loaded · 600 seconds             │
  │                                            │Save command: tmux-recovery snapshot --trigger timer --│
  │                                            │Next snapshot: 2026-07-21 01:42:39.000000000Z · estimat│
  │                                            │Autonomy tick: PASS · loaded · 45 seconds              │
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS WITH APPLICATION WARNING ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1 pane(s│
  │                                            │Applications: WARN · 1 shell fallback(s) · details belo│
  │                                            │Affected pane: development:0.0 (codex)                 │
  │                                            │Cause: Codex has no durable thread ID.                 │
  │                                            │Recovery: shell only; the application will not resume. │
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: PASS · valid native recovery point available│
  │                                            │Native history: 1 saved · rolling limit 10             │
  │                                            │Last good: 2026-07-21 01:32:39.000000000Z              │
  │                                            │Native storage: 8.0 KiB                                │
  │                                            │                                                       │
  │                                            │Automation                                             │
  │                                            │Readiness: PASS · tmux-recovery manages save and login │
  │                                            │Periodic save: PASS · loaded · 600 seconds             │
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- EMPTY STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1 pane(s│
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe restart│
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: WARN · no valid native recovery point; reboo│
  │                                            │Native history: 0 saved · rolling limit 10             │
  │                                            │Last good: none                                        │
  │                                            │Native storage: 0 B                                    │
  │                                            │                                                       │
  │                                            │Automation                                             │
  │                                            │Readiness: WARN · absent; inspect conflicts below      │
  │                                            │Periodic save: WARN · not installed                    │
  │                                            │Next snapshot: waiting for the first timer save        │
  │                                            │Autonomy tick: WARN · not installed                    │
  │                                            │Login restore: WARN · not installed                    │
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- UNAVAILABLE STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION                                 │ DETAIL                                                │
  │  Overview                                  │Status                                                 │
  │▾ Sessions  [online]                        │Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [attention]                       │Recovery                                               │
  │                                            │tmux: PASS · server running                            │
  │                                            │Workspace: PASS · 1 session(s) · 1 window(s) · 1 pane(s│
  │                                            │Applications: PASS · 0 exact resume(s) · 1 safe restart│
  │                                            │                                                       │
  │                                            │Snapshots                                              │
  │                                            │Readiness: WARN · snapshot inventory unavailable       │
  │                                            │fixture snapshot directory is unreadable               │
  │                                            │Press r to retry. Existing snapshot files are unchanged│
  │                                            │                                                       │
  │                                            │Automation                                             │
  │                                            │Readiness: WARN · service manager status unavailable   │
  │                                            │fixture service manager is unavailable                 │
  │                                            │Press r to retry. No automation settings were changed. │
  │                                            │                                                       │
  │                                            │Autonomous cleanup                                     │
  │                                            │Policy: off (no autonomous cleanup) · grace 1h 0m · can│
  │ ↑/↓ navigate · Enter expand/collapse · r refresh · q quit · c cancel · p pause                     │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
