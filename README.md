<p align="center">
  <img src="assets/logo.svg" alt="tmux-recovery logo" width="200">
</p>

<h1 align="center">tmux-recovery</h1>

<p align="center">
  Save a tmux workspace. Bring it back safely.
</p>

> Inspired by Jane Street's
> [“strace-ui, Bonsai_term, and the TUI renaissance”](https://blog.janestreet.com/strace-ui-bonsai-term-and-the-tui-renaissance/):
> a look at why terminal interfaces are having a well-deserved comeback.

`tmux-recovery` is a native OCaml CLI and TUI for inspecting, snapshotting, and
restoring tmux workspaces on macOS and Linux.

It remembers sessions, windows, panes, layouts, titles, working directories,
and the active pane. It can also safely restart a small set of known programs
and resume Codex panes when a durable thread ID is available.

<p align="center">
  <img src="assets/tmux-recovery-demo.gif" alt="tmux-recovery TUI navigating sessions, pane previews, and recovery status" width="100%">
</p>

## Install from source

The TUI currently requires the public OxCaml 5.2 toolchain used by
`Bonsai_term`.

```sh
git clone https://github.com/JonathanALevine/tmux-recovery.git
cd tmux-recovery

opam init -y --bare
opam update --all
opam switch create . 5.2.0+ox \
  --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test -y
opam install . -y
```

Open the TUI:

```sh
opam exec -- tmux-recovery
```

## Shell completion

Add the line for your shell to its startup file:

```sh
# ~/.zshrc
eval "$(tmux-recovery completion zsh)"

# ~/.bashrc
eval "$(tmux-recovery completion bash)"
```

Completion includes subcommands and their flags, so `tmux-recovery snap<Tab>`
offers `snapshot` and `snapshots`.

## TUI commands

Run `tmux-recovery` to open the TUI. Select an item in the tree to view its
details or live pane output. The detail pane follows the selection automatically.
Tab switches focus between navigation and the read-only detail viewer. A bright
blue, heavy rule beneath the active heading marks focus; the inactive rule is
muted and thin. Both rules keep their space when focus moves. The footer
shows `Tab detail · ↑/↓ navigate` when navigation has focus and
`Tab navigation · ↑/↓ scroll` when detail has focus. Headings align with their
pane's content, keeping the same position and color in both modes. On narrow terminals,
details appear below the tree. Long details scroll as one view, with the visible
line range in the heading. Status includes an **Affected panes** section identifying applications
that cannot resume, their locations, causes, and expected recovery results.
Use the CLI to save and restore workspaces or manage background services.

| Key | Action |
| --- | --- |
| <kbd>Tab</kbd> | Switch focus between navigation and detail |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Move through the tree, or scroll the focused detail viewer |
| <kbd>Enter</kbd> | Expand/collapse a navigation branch; no action on leaves or in detail |
| <kbd>Home</kbd> / <kbd>End</kbd> | Jump to the top/bottom of detail |
| <kbd>r</kbd> | Refresh workspace, snapshot, service, and pane-preview data |
| <kbd>c</kbd> | Cancel a pending autonomous cleanup action |
| <kbd>p</kbd> | Pause/resume autonomous cleanup |
| <kbd>q</kbd> | Quit |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> | Quit |

Run `tmux-recovery --socket NAME` to view a named tmux socket.
Shift-Tab, Page Up/Down, and left/right are unbound. Changing the selected tree item
resets detail scrolling; refresh and resizing keep the position within the
available content.
Without an interactive terminal, bare `tmux-recovery` prints help.

## Essential CLI commands

```sh
# Inspect
tmux-recovery status
tmux-recovery doctor
tmux-recovery snapshots list

# Save
tmux-recovery snapshot

# Restore the last known-good snapshot
tmux-recovery restore

# Install periodic save and login-restore services
tmux-recovery service status
tmux-recovery service sync
tmux-recovery service enable
```

Action commands execute directly. `snapshots prune` applies the retention policy,
preserving protected recovery points. Inspection commands such as `service plan`,
`processes plan`, and `status` remain available whenever you want more detail.

A restore refuses to run when the target already contains sessions. Use
`--socket recovery-test` to rehearse against a disposable named socket, or
`--no-applications` to restore only tmux structure and shells.

Run `tmux-recovery help` for the full command tree and
`tmux-recovery help COMMAND` for command-specific options.

## Autonomous cleanup

Cleanup defaults to **off**. Enable it with:

```sh
tmux-recovery autonomy configure --mode live
```

It only considers unviewed windows whose panes have all exited and have no recovery
action. Live or recoverable panes protect the entire window. Persistence and grace
periods, fresh eligibility checks, and snapshot-before-close remain in place.
Observation failures cancel pending cleanup and restart the eligibility period.

Use `autonomy status` to inspect the policy, `autonomy pause` / `autonomy resume`
to suspend/resume it, or `autonomy configure --mode off` to disable it.
The TUI's `c` and `p` keys control the same persisted pipeline; background services
continue operating independently of the TUI.

## Upgrading existing installations

The `--dry-run`, `--approve`, and prune's `--apply` flags have been removed.
Delete preview-only invocations from scripts unless you intend them to execute.
For commands that already execute, remove the obsolete flags. Action commands now
execute directly, including plain `snapshots prune`.
The explicit `ui` and `migrate` commands are also removed;
use bare `tmux-recovery` to open the TUI.

After rebuilding, regenerate existing managed service definitions so old arguments
are removed. Run these commands from the source checkout using the new executable:

```sh
opam exec -- dune exec bin/main.exe -- service disable
opam exec -- dune exec bin/main.exe -- service sync
opam exec -- dune exec bin/main.exe -- service enable
```

If you still use the old macOS scripts and launch agents, back up their definitions
and scripts before switching. Unload the old `com.jonathan.tmux-resurrect-save`
and `com.jonathan.tmux` agents with `launchctl bootout` and move their definitions
out of `~/Library/LaunchAgents`. Disable any other conflicting legacy timers or
tmux-resurrect/continuum automation, then use `service sync` and `service enable`.
`service status` identifies conflicts; enabling services still refuses unresolved
conflicts. Existing backup bundles under the data directory's `migrations/` folder
are retained for manual recovery.

Existing autonomy policies in `$XDG_CONFIG_HOME/tmux-recovery/autonomy.json` that
used the removed dry-run mode migrate to **off**. Their pending actions and
eligibility funnel are reset, so enabling live mode starts a fresh persistence
and grace period. Explicit off/live settings and paused state are preserved.
Old simulated audit events remain identified as simulations; state and history in
`$XDG_STATE_HOME/tmux-recovery/` do not need to be deleted.

## Development

```sh
opam exec -- dune fmt
opam exec -- dune build @all
opam exec -- dune runtest --force
```

Codex capture requires `ps` and `lsof` alongside tmux. On Debian/Ubuntu, install
`tmux procps lsof`; macOS includes `ps` and `lsof`.

Snapshots are stored under
`~/.local/share/tmux-recovery/snapshots/` by default.
