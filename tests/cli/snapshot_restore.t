Save and restore execute directly on a disposable, named tmux server. All files
and locks are isolated; no installed service or default tmux socket is used.

  $ export XDG_DATA_HOME="$PWD/data"
  $ export XDG_STATE_HOME="$PWD/state"
  $ export XDG_CONFIG_HOME="$PWD/config"
  $ export XDG_RUNTIME_DIR="$PWD/runtime"
  $ socket="tmux-recovery-cli-issue-11-$$"
  $ native="$PWD/native"
  $ trap 'tmux -L "$socket" kill-server 2>/dev/null || true' EXIT
  $ tmux -L "$socket" -f /dev/null new-session -d -s recovered -c /tmp /bin/sh
  $ tmux -L "$socket" set-option -g default-shell /bin/sh
  $ tmux -L "$socket" set-option -g default-command /bin/sh
  $ tmux -L "$socket" set-option -g exit-empty off
  $ ../../bin/headless.exe snapshot --socket "$socket" --native-directory "$native" --json > saved.json
  $ sed -n '/"saved":/p' saved.json
      "saved": true,
  $ test -f "$native/latest/snapshot.json"
  $ test -f "$native/last-good/snapshot.json"

An occupied target refuses restore and keeps the original pane intact. The
if-empty option succeeds without resolving a missing snapshot or replacing it.

  $ original=$(tmux -L "$socket" list-panes -a -F '#{pane_id}:#{pane_pid}')
  $ if ../../bin/headless.exe restore --socket "$socket" --native-directory "$native" --no-applications > occupied.txt 2>&1; then echo 'unexpectedly restored over existing sessions'; exit 1; fi
  $ grep -F 'restore target is not empty' occupied.txt > /dev/null
  $ test "$(tmux -L "$socket" list-panes -a -F '#{pane_id}:#{pane_pid}')" = "$original"
  $ ../../bin/headless.exe restore missing --socket "$socket" --native-directory "$native" --if-empty --json > skipped.json
  $ sed -n '/"restored":/p; /"noop":/p; /"reason":/p' skipped.json
      "restored": false,
      "noop": true,
      "reason": "target already contains sessions"
  $ test "$(tmux -L "$socket" list-panes -a -F '#{pane_id}:#{pane_pid}')" = "$original"

Once empty, plain restore reconstructs the snapshot with its default application
recovery policy and usable shell panes.

  $ tmux -L "$socket" kill-session -t recovered
  $ ../../bin/headless.exe restore --socket "$socket" --native-directory "$native" --json > restored.json
  $ sed -n '/"restored":/p; /"sessions":/p; /"windows":/p; /"panes":/p; /"applications":/p' restored.json
      "restored": true,
      "sessions": 1,
      "windows": 1,
      "panes": 1,
      "applications": true
  $ tmux -L "$socket" list-sessions -F '#{session_name}'
  recovered
  $ tmux -L "$socket" list-panes -a -F '#{pane_dead}'
  0

The optional structure-only restore also executes directly.

  $ tmux -L "$socket" kill-session -t recovered
  $ ../../bin/headless.exe snapshots restore --socket "$socket" --native-directory "$native" --no-applications --quiet
  $ tmux -L "$socket" list-sessions -F '#{session_name}'
  recovered
  $ tmux -L "$socket" list-panes -a -F '#{pane_dead}'
  0
  $ tmux -L "$socket" kill-server
