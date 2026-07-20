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
product requirements, accepted OCaml/OxCaml implementation model, TUI design,
distribution strategy, and fleet migration plan. It does not yet contain
application code and does not modify or enable any live service.

Open [architecture.html](architecture.html) in a browser for the complete
design notebook.

## Architecture decisions

The whole application will be implemented in OCaml: a pure typed domain and
application core, headless commands for automation, and a Bonsai_term TUI in
the same native executable. Users receive precompiled macOS and Linux binaries
and do not need OCaml, opam, Dune, OxCaml, Node, or npm.

Canonical versioned release archives are the source for every install channel.
The preferred managed installation is a Homebrew tap, with a checksum-verifying
user-local installer for machines without Homebrew:

```text
brew install JonathanALevine/tap/tmux-recovery
tmux-recovery setup
tmux-recovery
```

npm is optional and deferred; it is not required to install or run the product.
Services invoke a stable copy of the native executable, while shell remains
limited to the managed tmux-resurrect compatibility boundary. The detailed
library boundaries, TUI information architecture, transaction model, native
release targets, and implementation gates are recorded in `architecture.html`.

## Intended command surface

```text
tmux-recovery                  # open the TUI on an interactive terminal
tmux-recovery ui
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
