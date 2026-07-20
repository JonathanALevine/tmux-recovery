# tmux-recovery

Service-managed orchestration for reliable tmux persistence across macOS and
Linux.

The project keeps `tmux-resurrect` as the snapshot and reconstruction engine,
then adds the lifecycle controls needed for unattended operation:

- guarded and serialized saves;
- startup and shutdown integration;
- staged restore drivers;
- policy-driven restart of ordinary pane applications;
- application-aware resume for tools such as Codex;
- systemd user units and macOS LaunchAgents;
- installation, diagnostics, and migration tooling.

The repository is currently specification-only. It contains the architecture,
product requirements, accepted Go implementation model, distribution strategy,
and fleet migration plan. It does not yet contain application code and does not
modify or enable any live service.

Open [architecture.html](architecture.html) in a browser for the complete
design notebook.

## Architecture decision

The native CLI will be implemented in Go and distributed as precompiled
macOS and Linux binaries. The primary installation experience will use a small
npm launcher with platform-specific optional packages:

```text
npm install -g tmux-recovery
tmux-recovery setup
```

Go runs the product core, services invoke a stable copy of the native binary,
and shell remains limited to the managed tmux-resurrect compatibility boundary.
The detailed package boundaries, transaction model, release targets, and
implementation gates are recorded in `architecture.html`.

## Intended command surface

```text
tmux-recovery setup
tmux-recovery save
tmux-recovery restore
tmux-recovery status
tmux-recovery doctor
tmux-recovery processes plan
tmux-recovery service status
tmux-recovery service enable
tmux-recovery service disable
tmux-recovery migrate
```

## Project boundary

Versioned here:

- product and architecture specifications;
- future CLI and lifecycle code;
- service templates;
- tmux integration;
- process strategies;
- host profiles;
- tests and documentation.

Never versioned here:

- tmux-resurrect snapshots or pane contents;
- Codex SQLite databases or session files;
- runtime locks;
- service logs;
- SSH routing or credentials.
