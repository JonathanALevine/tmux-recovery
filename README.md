# tmux-steward

Service-managed orchestration for reliable tmux persistence across macOS and
Linux.

The project keeps `tmux-resurrect` as the snapshot and reconstruction engine,
then adds the lifecycle controls needed for unattended operation:

- guarded and serialized saves;
- startup and shutdown integration;
- staged restore drivers;
- process-aware Codex restoration;
- systemd user units and macOS LaunchAgents;
- installation, diagnostics, and migration tooling.

The initial repository contains the architecture and implementation plan. It
does not modify or enable any live service.

Open [architecture.html](architecture.html) in a browser for the complete
design notebook.

## Intended command surface

```text
tmux-steward save
tmux-steward restore
tmux-steward status
tmux-steward doctor
tmux-steward service install
tmux-steward service enable
tmux-steward service disable
tmux-steward migrate
```

## Project boundary

Versioned here:

- lifecycle code;
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

