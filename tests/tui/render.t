  $ ./render_fixture.exe
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │tmux-recovery                                          │
  │▾ Sessions  [online]                        │A conservative recovery control plane for tmux.        │
  │  ▸ development  [attached]                 │                                                       │
  │  Status  [ready]                           │tmux: online                                           │
  │                                            │Sessions: 1                                            │
  │                                            │Canonical windows: 1                                   │
  │                                            │Panes: 1                                               │
  │                                            │Native snapshots: 1 saved · rolling limit 10           │
  │                                            │                                                       │
  │                                            │Guarded mutations require explicit approval in the CLI.│
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
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- MOVED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
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
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- WINDOW SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ PREVIEW                                               │
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
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- PANE SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ PREVIEW                                               │
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
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
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
  │                                            │Login restore: PASS · loaded · at login                │
  │                                            │Runtime version: 0.3.0-dev.10                          │
  │                                            │Last result: launchctl exit status 0                   │
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- STATUS WITH APPLICATION WARNING ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
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
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- EMPTY STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
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
  │                                            │Login restore: WARN · not installed                    │
  │                                            │Runtime version: unknown                               │
  │                                            │Last result: unavailable                               │
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- UNAVAILABLE STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
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
  │                                            │Mutation safety: PASS · destructive operations require │
  │                                            │Use the CLI for snapshot restore and automation changes│
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
