  $ ./render_fixture.exe
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │tmux-recovery                                          │
  │▾ Sessions  [online]                        │A conservative recovery control plane for tmux.        │
  │  ▸ development  [attached]                 │                                                       │
  │▸ Snapshots  [1]                            │tmux: online                                           │
  │  Recovery plan                             │Sessions: 1                                            │
  │  Services  [legacy/unmanaged]              │Canonical windows: 1                                   │
  │  Doctor                                    │Panes: 1                                               │
  │                                            │Snapshots: 1                                           │
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
  │▸ Snapshots  [1]                            │Version: tmux test                                     │
  │  Recovery plan                             │Socket: default                                        │
  │  Services  [legacy/unmanaged]              │                                                       │
  │  Doctor                                    │                                                       │
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
  │▸ Snapshots  [1]                            │Active pane · bottom of screen · read-only · refresh wi│
  │  Recovery plan                             │                                                       │
  │  Services  [legacy/unmanaged]              │older output 01                                        │
  │  Doctor                                    │older output 02                                        │
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
  │▸ Snapshots  [1]                            │Recovery: restart                                      │
  │  Recovery plan                             │                                                       │
  │  Services  [legacy/unmanaged]              │Latest pane output                                     │
  │  Doctor                                    │Bottom of pane · read-only · refresh with r            │
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
  
  --- SNAPSHOTS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │Snapshots                                              │
  │▾ Sessions  [online]                        │Directory: /Users/demo/.local/share/tmux/resurrect     │
  │  ▸ development  [attached]                 │Directory health: available                            │
  │▸ Snapshots  [1]                            │Total: 1                                               │
  │  Recovery plan                             │Valid: 1                                               │
  │  Services  [legacy/unmanaged]              │Newest: 2026-07-20 21:32:39                            │
  │  Doctor                                    │Last good: tmux_resurrect_20260720T213239.txt          │
  │                                            │Storage: 4.0 KiB                                       │
  │                                            │Retention: native: keep 5 and 30 days · legacy: preserv│
  │                                            │                                                       │
  │                                            │Expand Snapshots to inspect immutable saved entries.   │
  │                                            │Captured pane contents and full commands are not displa│
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
  
  --- SNAPSHOT SELECTED ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │2026-07-20 21:32:39                                    │
  │▾ Sessions  [online]                        │Source ID: tmux_resurrect_20260720T213239.txt          │
  │  ▸ development  [attached]                 │Validity: valid                                        │
  │▾ Snapshots  [1]                            │Status: latest last-good legacy                        │
  │    2026-07-20 21:32:39  [latest last-good l│Sessions: 1                                            │
  │  Recovery plan                             │Windows: 1                                             │
  │  Services  [legacy/unmanaged]              │Panes: 1                                               │
  │  Doctor                                    │Size: 4.0 KiB                                          │
  │                                            │Process manifest: absent                               │
  │                                            │Compatibility: legacy/upstream                         │
  │                                            │                                                       │
  │                                            │Use snapshots restore --dry-run before approving restor│
  │                                            │Snapshot structure is valid.                           │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │                                            │                                                       │
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- SERVICES ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │Services                                               │
  │▾ Sessions  [online]                        │Manager: launchd                                       │
  │  ▸ development  [attached]                 │Ownership: legacy/unmanaged                            │
  │▸ Snapshots  [1]                            │Periodic save                                          │
  │  Recovery plan                             │Status: loaded · 600 seconds                           │
  │  Services  [legacy/unmanaged]              │Definition: /Users/demo/Library/LaunchAgents/com.demo.t│
  │  Doctor                                    │Login restore                                          │
  │                                            │Status: loaded · at login                              │
  │                                            │Definition: /Users/demo/Library/LaunchAgents/com.demo.t│
  │                                            │Runtime binary                                         │
  │                                            │Path: /Users/demo/bin/tmux-resurrect-save-safe         │
  │                                            │Version: unknown                                       │
  │                                            │Recent result                                          │
  │                                            │Last result: launchctl exit status 0                   │
  │                                            │Next run: unavailable                                  │
  │                                            │Conflicts: 0                                           │
  │                                            │Warning: legacy tmux automation detected; tmux-recovery│
  │                                            │Service mutations require reviewed CLI --approve flags.│
  │                                            │                                                       │
  │                                            │                                                       │
  │ ↑/↓ or j/k move  ←/→ or h/l fold  enter open  tab focus  r refresh  q quit                         │
  └────────────────────────────────────────────────────────────────────────────────────────────────────┘
  
  --- EMPTY SNAPSHOTS ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │Snapshots                                              │
  │▾ Sessions  [online]                        │Directory: /Users/demo/.local/share/tmux/resurrect     │
  │  ▸ development  [attached]                 │Directory health: available                            │
  │  Snapshots  [0]                            │Total: 0                                               │
  │  Recovery plan                             │Valid: 0                                               │
  │  Services  [absent]                        │Newest: none                                           │
  │  Doctor                                    │Last good: none                                        │
  │                                            │Storage: 0 B                                           │
  │                                            │Retention: native: keep 5 and 30 days · legacy: preserv│
  │                                            │                                                       │
  │                                            │Expand Snapshots to inspect immutable saved entries.   │
  │                                            │Captured pane contents and full commands are not displa│
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
  
  --- UNAVAILABLE INVENTORIES ---
  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ NAVIGATION ◀                               │ DETAIL                                                │
  │  Overview                                  │Snapshots unavailable                                  │
  │▾ Sessions  [online]                        │fixture snapshot directory is unreadable               │
  │  ▸ development  [attached]                 │                                                       │
  │  Snapshots  [unavailable]                  │Press r to retry. No snapshot files were changed.      │
  │  Recovery plan                             │                                                       │
  │  Services  [unavailable]                   │                                                       │
  │  Doctor                                    │                                                       │
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
  
