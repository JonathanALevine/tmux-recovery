  $ ./render_fixture.exe
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃tmux-recovery                                          │
  │▾ Sessions  [online]                        ┃A conservative recovery control plane for tmux.        │
  │  ▸ development  [attached]                 ┃                                                       │
  │▾ Status  [ready]                           ┃tmux: online                                           │
  │    Recovery                                ┃Sessions: 1                                            │
  │    Affected panes  [0]                     ┃Canonical windows: 1                                   │
  │    Snapshots                               ┃Panes: 1                                               │
  │    Automation                              ┃Native snapshots: 1 saved · rolling limit 10           │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃Use snapshot to save and restore to recover your       │
  │                                            ┃workspace.                                             │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- MOVED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Sessions                                               │
  │▾ Sessions  [online]                        ┃Source: live                                           │
  │  ▸ development  [attached]                 ┃Server: running                                        │
  │▾ Status  [ready]                           ┃Version: tmux test                                     │
  │    Recovery                                ┃Socket: default                                        │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- WINDOW SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃PREVIEW                                                │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃monitoring                                             │
  │▾ Sessions  [online]                        ┃Window 0 · active pane 0 · btop                        │
  │  ▾ development  [attached]                 ┃                                                       │
  │    ▸ 0:monitoring  [active]                ┃Live window contents                                   │
  │▾ Status  [ready]                           ┃Active pane · bottom of screen · read-only · refresh wi│
  │    Recovery                                ┃                                                       │
  │    Affected panes  [0]                     ┃older output 02                                        │
  │    Snapshots                               ┃older output 03                                        │
  │    Automation                              ┃older output 04                                        │
  │    Autonomous cleanup                      ┃older output 05                                        │
  │    Recovery safety                         ┃older output 06                                        │
  │                                            ┃older output 07                                        │
  │                                            ┃older output 08                                        │
  │                                            ┃older output 09                                        │
  │                                            ┃older output 10                                        │
  │                                            ┃older output 11                                        │
  │                                            ┃older output 12                                        │
  │                                            ┃$ printf 'latest pane output\n'                        │
  │                                            ┃latest btop output                                     │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- PANE SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃PREVIEW                                                │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Pane 0                                                 │
  │▾ Sessions  [online]                        ┃Typed ID: %1                                           │
  │  ▾ development  [attached]                 ┃Working directory: /Users/demo                         │
  │    ▾ 0:monitoring  [active]                ┃Title: btop                                            │
  │      ▸ pane 0  [active]                    ┃Observed command: btop                                 │
  │▾ Status  [ready]                           ┃Recovery: restart                                      │
  │    Recovery                                ┃                                                       │
  │    Affected panes  [0]                     ┃Latest pane output                                     │
  │    Snapshots                               ┃Bottom of pane · read-only · refresh with r            │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃older output 06                                        │
  │    Recovery safety                         ┃older output 07                                        │
  │                                            ┃older output 08                                        │
  │                                            ┃older output 09                                        │
  │                                            ┃older output 10                                        │
  │                                            ┃older output 11                                        │
  │                                            ┃older output 12                                        │
  │                                            ┃$ printf 'latest pane output\n'                        │
  │                                            ┃latest btop output                                     │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW PANE ---
  ┌────────────────────────────────────────────────────────────┐
  │NAVIGATION                                                  │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  ▾ development  [attached]                                 │
  │    ▾ 0:monitoring  [active]                                │
  │      ▸ pane 0  [active]                                    │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │PREVIEW                                                     │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
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
  │older output 12                                             │
  │$ printf 'latest pane output\n'                             │
  │latest btop output                                          │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refre│
  └────────────────────────────────────────────────────────────┘
  --- SHORT NARROW PANE ---
  ┌────────────────────────────────────────┐
  │NAVIGATION                              │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │      ▸ pane 0  [active]                │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │PREVIEW                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │Pane 0 · btop                           │
  │Recovery: restart                       │
  │Latest pane output                      │
  │older output 11                         │
  │older output 12                         │
  │$ printf 'latest pane output\n'         │
  │latest btop output                      │
  │ Tab detail     · ↑/↓ move · Enter expan│
  └────────────────────────────────────────┘
  --- RESIZED WIDE AGAIN ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃PREVIEW                                                │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Pane 0                                                 │
  │▾ Sessions  [online]                        ┃Typed ID: %1                                           │
  │  ▾ development  [attached]                 ┃Working directory: /Users/demo                         │
  │    ▾ 0:monitoring  [active]                ┃Title: btop                                            │
  │      ▸ pane 0  [active]                    ┃Observed command: btop                                 │
  │▾ Status  [ready]                           ┃Recovery: restart                                      │
  │    Recovery                                ┃                                                       │
  │    Affected panes  [0]                     ┃Latest pane output                                     │
  │    Snapshots                               ┃Bottom of pane · read-only · refresh with r            │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃older output 06                                        │
  │    Recovery safety                         ┃older output 07                                        │
  │                                            ┃older output 08                                        │
  │                                            ┃older output 09                                        │
  │                                            ┃older output 10                                        │
  │                                            ┃older output 11                                        │
  │                                            ┃older output 12                                        │
  │                                            ┃$ printf 'latest pane output\n'                        │
  │                                            ┃latest btop output                                     │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Status                                                 │
  │▾ Sessions  [online]                        ┃Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 ┃                                                       │
  │▾ Status  [ready]                           ┃Readiness: ready                                       │
  │    Recovery                                ┃Affected panes: 0                                      │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃Select a section under Status to inspect its details.  │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS COLLAPSED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Status                                                 │
  │▾ Sessions  [online]                        ┃Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 ┃                                                       │
  │▸ Status  [ready]                           ┃Readiness: ready                                       │
  │                                            ┃Affected panes: 0                                      │
  │                                            ┃                                                       │
  │                                            ┃Select a section under Status to inspect its details.  │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- STATUS WITH APPLICATION WARNING ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Status                                                 │
  │▾ Sessions  [online]                        ┃Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 ┃                                                       │
  │▾ Status  [attention]                       ┃Readiness: attention                                   │
  │    Recovery                                ┃Affected panes: 1                                      │
  │  ▸ Affected panes  [1]                     ┃                                                       │
  │    Snapshots                               ┃Select a section under Status to inspect its details.  │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- RECOVERY SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Recovery                                               │
  │▾ Sessions  [online]                        ┃tmux: PASS · server running                            │
  │  ▸ development  [attached]                 ┃Workspace: PASS · 1 session(s) · 1 window(s) · 1       │
  │▾ Status  [attention]                       ┃pane(s)                                                │
  │    Recovery                                ┃Applications: WARN · 1 shell fallback(s) · see Affected│
  │  ▸ Affected panes  [1]                     ┃panes                                                  │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AFFECTED PANES SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Affected panes (1)                                     │
  │▾ Sessions  [online]                        ┃                                                       │
  │  ▸ development  [attached]                 ┃development:0.0 · %1                                   │
  │▾ Status  [attention]                       ┃Application: codex                                     │
  │    Recovery                                ┃Cause: Codex has no durable thread ID.                 │
  │  ▸ Affected panes  [1]                     ┃Recovery: shell only; the application will not resume. │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- SNAPSHOTS SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Snapshots                                              │
  │▾ Sessions  [online]                        ┃Readiness: PASS · valid native recovery point available│
  │  ▸ development  [attached]                 ┃Native history: 1 saved · rolling limit 10             │
  │▾ Status  [attention]                       ┃Last good: 2026-07-21 01:32:39.000000000Z              │
  │    Recovery                                ┃Native storage: 8.0 KiB                                │
  │  ▸ Affected panes  [1]                     ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AUTOMATION SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Automation                                             │
  │▾ Sessions  [online]                        ┃Readiness: PASS · tmux-recovery manages save and login │
  │  ▸ development  [attached]                 ┃restore                                                │
  │▾ Status  [attention]                       ┃Periodic save: PASS · loaded · 600 seconds             │
  │    Recovery                                ┃Next snapshot: 2026-07-21 01:42:39.000000000Z ·        │
  │  ▸ Affected panes  [1]                     ┃estimated from the last timer save                     │
  │    Snapshots                               ┃Cleanup checks: PASS · loaded · 45 seconds             │
  │    Automation                              ┃Login restore: PASS · loaded · at login                │
  │    Autonomous cleanup                      ┃Last restore run: 2026-07-21 01:30:00.000000000Z ·     │
  │    Recovery safety                         ┃restored                                               │
  │                                            ┃tmux_recovery_1784597559000000000_0123abcd.snapshot    │
  │                                            ┃Runtime version: 0.3.0-dev.14                          │
  │                                            ┃Last result: launchctl exit status 0                   │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AUTONOMOUS CLEANUP SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Autonomous cleanup                                     │
  │▾ Sessions  [online]                        ┃Policy: off (no autonomous cleanup) · grace 1h 0m ·    │
  │  ▸ development  [attached]                 ┃candidate for ≥ 15m 0s · snapshot before               │
  │▾ Status  [attention]                       ┃fire: yes                                              │
  │    Recovery                                ┃Pending actions: 0                                     │
  │  ▸ Affected panes  [1]                     ┃No windows are currently scheduled for autonomous      │
  │    Snapshots                               ┃close.                                                 │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃Eligibility funnel: empty.                             │
  │    Recovery safety                         ┃No autonomous actions recorded yet.                    │
  │                                            ┃p pauses or resumes the pipeline.                      │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- RECOVERY SAFETY SECTION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Recovery safety                                        │
  │▾ Sessions  [online]                        ┃Snapshot integrity and occupied targets are checked.   │
  │  ▸ development  [attached]                 ┃Use the CLI for snapshot restore and automation        │
  │▾ Status  [attention]                       ┃changes.                                               │
  │    Recovery                                ┃                                                       │
  │  ▸ Affected panes  [1]                     ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AFFECTED PANES DROPDOWN CLOSED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Affected panes (1)                                     │
  │▾ Sessions  [online]                        ┃                                                       │
  │  ▸ development  [attached]                 ┃development:0.0 · %1                                   │
  │▾ Status  [attention]                       ┃Application: codex                                     │
  │    Recovery                                ┃Cause: Codex has no durable thread ID.                 │
  │  ▸ Affected panes  [1]                     ┃Recovery: shell only; the application will not resume. │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AFFECTED PANES DROPDOWN OPEN ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Affected panes (1)                                     │
  │▾ Sessions  [online]                        ┃                                                       │
  │  ▸ development  [attached]                 ┃development:0.0 · %1                                   │
  │▾ Status  [attention]                       ┃Application: codex                                     │
  │    Recovery                                ┃Cause: Codex has no durable thread ID.                 │
  │  ▾ Affected panes  [1]                     ┃Recovery: shell only; the application will not resume. │
  │      development:0.0 · codex  [%1]         ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AFFECTED PANE SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃development:0.0                                        │
  │▾ Sessions  [online]                        ┃Pane: %1                                               │
  │  ▸ development  [attached]                 ┃Application: codex                                     │
  │▾ Status  [attention]                       ┃                                                       │
  │    Recovery                                ┃Cause: Codex has no durable thread ID.                 │
  │  ▾ Affected panes  [1]                     ┃Recovery: shell only; the application will not resume. │
  │      development:0.0 · codex  [%1]         ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW AFFECTED PANE ---
  ┌────────────────────────────────────────┐
  │NAVIGATION                              │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │      development:0.0 · codex  [%1]     │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │DETAIL                                  │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │development:0.0                         │
  │Pane: %1                                │
  │Application: codex                      │
  │                                        │
  │Cause: Codex has no durable thread ID.  │
  │Recovery: shell only; the application   │
  │will not resume.                        │
  │ Tab detail     · ↑/↓ move · Enter expan│
  └────────────────────────────────────────┘
  --- FOCUSED AFFECTED PANES DETAILS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL · 1–19/151                                      │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Affected panes (30)                                    │
  │▾ Sessions  [online]                        ┃                                                       │
  │  ▸ development  [attached]                 ┃development:0.0 · %1                                   │
  │▾ Status  [attention]                       ┃Application: codex                                     │
  │    Recovery                                ┃Cause: Cannot resume application in pane %1.           │
  │  ▸ Affected panes  [30]                    ┃Recovery: shell only; the application will not resume. │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃development:0.1 · %2                                   │
  │    Autonomous cleanup                      ┃Application: codex                                     │
  │    Recovery safety                         ┃Cause: Cannot resume application in pane %2.           │
  │                                            ┃Recovery: shell only; the application will not resume. │
  │                                            ┃                                                       │
  │                                            ┃development:0.2 · %3                                   │
  │                                            ┃Application: codex                                     │
  │                                            ┃Cause: Cannot resume application in pane %3.           │
  │                                            ┃Recovery: shell only; the application will not resume. │
  │                                            ┃                                                       │
  │                                            ┃development:0.3 · %4                                   │
  │                                            ┃Application: codex                                     │
  │ Tab navigation · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- AFFECTED PANES SCROLLED TO END ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL · 133–151/151                                   │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃development:0.26 · %27                                 │
  │▾ Sessions  [online]                        ┃Application: codex                                     │
  │  ▸ development  [attached]                 ┃Cause: Cannot resume application in pane %27.          │
  │▾ Status  [attention]                       ┃Recovery: shell only; the application will not resume. │
  │    Recovery                                ┃                                                       │
  │  ▸ Affected panes  [30]                    ┃development:0.27 · %28                                 │
  │    Snapshots                               ┃Application: codex                                     │
  │    Automation                              ┃Cause: Cannot resume application in pane %28.          │
  │    Autonomous cleanup                      ┃Recovery: shell only; the application will not resume. │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃development:0.28 · %29                                 │
  │                                            ┃Application: codex                                     │
  │                                            ┃Cause: Cannot resume application in pane %29.          │
  │                                            ┃Recovery: shell only; the application will not resume. │
  │                                            ┃                                                       │
  │                                            ┃development:0.29 · %30                                 │
  │                                            ┃Application: codex                                     │
  │                                            ┃Cause: Cannot resume application in pane %30.          │
  │                                            ┃Recovery: shell only; the application will not resume. │
  │ Tab navigation · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- NARROW AFFECTED PANES ---
  ┌────────────────────────────────────────┐
  │NAVIGATION                              │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  ▸ Affected panes  [30]                │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │DETAIL · 1–7/211                        │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │Affected panes (30)                     │
  │                                        │
  │development:0.0 · %1                    │
  │Application: codex                      │
  │Cause: Cannot resume application in pane│
  │%1.                                     │
  │Recovery: shell only; the application   │
  │ Tab navigation · ↑/↓ move · Enter expan│
  └────────────────────────────────────────┘
  --- EMPTY STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Status                                                 │
  │▾ Sessions  [online]                        ┃Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 ┃                                                       │
  │▾ Status  [attention]                       ┃Readiness: attention                                   │
  │    Recovery                                ┃Affected panes: 0                                      │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃Select a section under Status to inspect its details.  │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- EMPTY SNAPSHOTS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Snapshots                                              │
  │▾ Sessions  [online]                        ┃Readiness: WARN · no valid native recovery point;      │
  │  ▸ development  [attached]                 ┃reboot recovery is unsafe                              │
  │▾ Status  [attention]                       ┃Native history: 0 saved · rolling limit 10             │
  │    Recovery                                ┃Last good: none                                        │
  │    Affected panes  [0]                     ┃Native storage: 0 B                                    │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- EMPTY AUTOMATION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Automation                                             │
  │▾ Sessions  [online]                        ┃Readiness: WARN · absent; inspect conflicts below      │
  │  ▸ development  [attached]                 ┃Periodic save: WARN · not installed                    │
  │▾ Status  [attention]                       ┃Next snapshot: waiting for the first timer save        │
  │    Recovery                                ┃Cleanup checks: WARN · not installed                   │
  │    Affected panes  [0]                     ┃Login restore: WARN · not installed                    │
  │    Snapshots                               ┃Last restore run: not recorded yet                     │
  │    Automation                              ┃Runtime version: unknown                               │
  │    Autonomous cleanup                      ┃Last result: unavailable                               │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- UNAVAILABLE STATUS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Status                                                 │
  │▾ Sessions  [online]                        ┃Recovery readiness, snapshot history, and automation.  │
  │  ▸ development  [attached]                 ┃                                                       │
  │▾ Status  [attention]                       ┃Readiness: attention                                   │
  │    Recovery                                ┃Affected panes: 0                                      │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃Select a section under Status to inspect its details.  │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- UNAVAILABLE SNAPSHOTS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Snapshots                                              │
  │▾ Sessions  [online]                        ┃Readiness: WARN · snapshot inventory unavailable       │
  │  ▸ development  [attached]                 ┃fixture snapshot directory is unreadable               │
  │▾ Status  [attention]                       ┃Press r to retry. Existing snapshot files are          │
  │    Recovery                                ┃unchanged.                                             │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  --- UNAVAILABLE AUTOMATION ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │NAVIGATION                                  ┃DETAIL                                                 │
  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│
  │  Overview                                  ┃Automation                                             │
  │▾ Sessions  [online]                        ┃Readiness: WARN · service manager status unavailable   │
  │  ▸ development  [attached]                 ┃fixture service manager is unavailable                 │
  │▾ Status  [attention]                       ┃Press r to retry. No automation settings were changed. │
  │    Recovery                                ┃                                                       │
  │    Affected panes  [0]                     ┃                                                       │
  │    Snapshots                               ┃                                                       │
  │    Automation                              ┃                                                       │
  │    Autonomous cleanup                      ┃                                                       │
  │    Recovery safety                         ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │                                            ┃                                                       │
  │ Tab detail     · ↑/↓ move · Enter expand/collapse · r refresh · q quit · p pause                   │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
