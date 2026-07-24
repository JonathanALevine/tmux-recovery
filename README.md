# tmux-recovery

`tmux-recovery` is a native OCaml CLI and Bonsai_term TUI that saves and
reconstructs tmux workspaces. It owns the snapshot format, guarded restore
engine, application restart policy, and launchd/systemd scheduling; it does not
depend on tmux-resurrect, tmux-continuum, or personal wrapper scripts.

Existing tmux-resurrect files remain visible and can be imported read-only.
SQLite is not used for workspace snapshots. The built-in Codex adapter opens
Codex's provider databases read-only to associate a pane with a durable thread
ID; conversation content and arbitrary database rows are never copied.

## What works

- Atomic, hashed native snapshot bundles under
  `~/.local/share/tmux-recovery/snapshots/`.
- Atomic `latest` and `last-good` pointers, per-socket locking, validation, and
  rolling retention of the newest ten native snapshots.
- Empty-target-only restore of sessions, canonical/shared windows, panes,
  indexes, active state, layouts, titles, and working directories.
- Exact Codex conversation resume using an explicit `codex resume <UUID>` first,
  then process-to-thread evidence. The newest active thread for a pane working
  directory is used only as an unambiguous compatibility fallback. A detected
  Codex pane without a durable provider thread is recorded and reported as
  blocked instead of silently resuming the wrong conversation. Existing
  unrestricted session policy is preserved, not introduced.
- Approved direct application restarts for btop, htop, top, bare
  Python/IPython, and tmux-recovery's own interactive navigator. Approved
  programs are resolved to verified absolute paths so login services do not
  depend on an interactive shell's `PATH`. Unknown programs fall back to usable
  shells.
- Backward-compatible native snapshot reader for schema v1 and a schema v2
  writer containing minimal application resume records.
- Read-only conversion of compatible tmux-resurrect snapshots to native
  bundles without invoking plugin scripts or replaying saved command text.
- Stable versioned service runtime with atomic sync and rollback.
- Native launchd and systemd user definitions. Service files call the stable
  binary directly; there is no resident daemon or shell wrapper.
- Reversible legacy migration with checksummed rollback bundles.
- Keyboard-only TUI with terminal-theme colors, bottom-of-pane live previews,
  and one combined Status page for recovery, snapshots, and automation.

All external processes use explicit argument arrays. Captured pane text and
saved full command strings are never evaluated as shell commands.

## Install from a checkout

The TUI currently uses the public OxCaml 5.2 toolchain required by Bonsai_term.

```sh
opam init -y --bare
opam update --all
git clone git@github.com:JonathanALevine/tmux-recovery.git
cd tmux-recovery
opam switch create . 5.2.0+ox \
  --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test -y
opam exec -- dune build @all
```

Install the built executable through opam:

```sh
opam install .
```

Or expose a development build directly:

```sh
ln -s "$PWD/_build/default/bin/main.exe" ~/bin/tmux-recovery
```

Verify the selected executable:

```sh
which tmux-recovery
tmux-recovery --version
```

The distribution path is native release archives plus Homebrew bottles and an
opam package. npm is unnecessary because the deliverable is one native binary.

## CLI

Read and inspect:

```sh
tmux-recovery status
tmux-recovery tree
tmux-recovery processes plan
tmux-recovery snapshots list
tmux-recovery service status
tmux-recovery doctor
```

Save, validate, import, and prune:

```sh
tmux-recovery snapshot --dry-run
tmux-recovery snapshot
tmux-recovery restore --dry-run
tmux-recovery restore --approve
tmux-recovery snapshots validate last-good
tmux-recovery snapshots import-resurrect LEGACY_ID --dry-run
tmux-recovery snapshots import-resurrect LEGACY_ID --approve
tmux-recovery snapshots prune --dry-run
tmux-recovery snapshots prune --apply
```

Restore first into a named disposable tmux socket:

```sh
tmux-recovery restore --socket recovery-test --dry-run
tmux-recovery restore --socket recovery-test --approve
```

A real restore requires `--approve` and refuses a target that already contains
sessions. `--if-empty` turns that condition into a successful no-op for login
services. Add `--no-applications` to reconstruct only tmux structure and shells.

Managed services:

```sh
tmux-recovery service plan
tmux-recovery service sync --dry-run
tmux-recovery service sync --approve
tmux-recovery service enable --dry-run
tmux-recovery service enable --approve
tmux-recovery service disable --dry-run
tmux-recovery service disable --approve
tmux-recovery service rollback --approve
```

Legacy cutover is intentionally separate:

```sh
tmux-recovery migrate status
tmux-recovery migrate plan
tmux-recovery migrate apply --approve
tmux-recovery migrate rollback --approve
```

Most inspection and planning commands also support a stable schema-1 `--json`
envelope.

### Complete command reference

Running `tmux-recovery` with no arguments in an interactive terminal opens the
TUI. `tmux-recovery help COMMAND` prints the flags and arguments for any command
below.

```text
tmux-recovery
tmux-recovery ui
tmux-recovery status
tmux-recovery tree
tmux-recovery snapshot [--dry-run]
tmux-recovery restore [last-good|latest|SNAPSHOT_ID] [--dry-run|--approve]
tmux-recovery doctor
tmux-recovery version
tmux-recovery help [COMMAND ...]

tmux-recovery processes plan

tmux-recovery snapshots list
tmux-recovery snapshots show SNAPSHOT_ID
tmux-recovery snapshots save [--dry-run]
tmux-recovery snapshots restore [last-good|latest|SNAPSHOT_ID] [--dry-run|--approve]
tmux-recovery snapshots validate SELECTOR
tmux-recovery snapshots prune [--dry-run|--apply]
tmux-recovery snapshots import-resurrect LEGACY_ID (--dry-run|--approve)

tmux-recovery service status
tmux-recovery service plan
tmux-recovery service sync (--dry-run|--approve)
tmux-recovery service rollback --approve
tmux-recovery service enable (--dry-run|--approve)
tmux-recovery service disable (--dry-run|--approve)

tmux-recovery migrate status
tmux-recovery migrate plan
tmux-recovery migrate apply --approve
tmux-recovery migrate rollback --approve
```

`snapshot` is the preferred save command and `restore` is the preferred restore
command. The plural `snapshots save` and `snapshots restore` forms remain
available for compatibility. `restore` defaults to `last-good`; use `--dry-run`
to inspect its plan and `--approve` to execute it. Mutating service, migration,
import, restore, sync, and pruning operations retain their command-specific
approval flags.

## TUI

Run `tmux-recovery` in an interactive terminal or use `tmux-recovery ui`.

- `j`/`k` or arrows move.
- `h`/`l` collapse and expand.
- `Enter` opens or toggles a branch.
- `Tab` switches panes on narrow terminals.
- `r` refreshes sessions, combined status, and the selected live preview.
- `q` or `Ctrl-C` exits.

The TUI inherits the terminal foreground/background, disables mouse reporting,
starts individual sessions collapsed, and shows the newest visible lines from
the active pane of a selected window. Safe SGR colors such as btop's palette are
preserved; other terminal controls are neutralized.

## Development and tests

```sh
opam exec -- dune fmt
opam exec -- dune build @all
opam exec -- dune runtest --force
```

Run one area:

```sh
opam exec -- dune runtest tests/domain --force
opam exec -- dune runtest tests/adapters --force
opam exec -- dune runtest tests/tui --force
```

Dune is quiet when tests pass. Use `--verbose` to see every executed test
command. The TUI suite is a Cram golden test; review and promote an intentional
screen diff with `opam exec -- dune promote tests/tui/render.t`.

`tmux-recovery.opam` is generated from `dune-project`; the `.opam.locked` file
pins the tested dependency graph and belongs in version control.

## Architecture

```text
cli / tui
    │
application       plan → validate → apply → verify → rollback
    │
domain            workspace graph, policies, plans, results
    │
adapters          tmux, snapshot store, launchd/systemd, legacy import
```

Local architecture and migration notes live under the gitignored `dev/`
directory. Existing tmux-resurrect snapshot history is user data and is never
deleted by routine migration or retention.
