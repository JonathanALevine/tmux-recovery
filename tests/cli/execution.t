All mutations below use isolated XDG directories. Rejected arguments must be
caught by the parser, before any runtime, snapshot, or policy is written.

  $ export XDG_DATA_HOME="$PWD/data"
  $ export XDG_STATE_HOME="$PWD/state"
  $ export XDG_CONFIG_HOME="$PWD/config"
  $ export XDG_RUNTIME_DIR="$PWD/runtime"
  $ runtime="$XDG_DATA_HOME/tmux-recovery/bin"
  $ reject () { obsolete="$1"; shift; if ../../bin/headless.exe "$@" "$obsolete" > rejected.txt 2>&1; then echo "unexpectedly accepted $obsolete: $*"; return 1; fi; grep -F "unknown flag $obsolete" rejected.txt > /dev/null; }
  $ for obsolete in --dry-run --approve; do
  >   reject "$obsolete" snapshot || exit 1
  >   reject "$obsolete" snapshots save || exit 1
  >   reject "$obsolete" restore || exit 1
  >   reject "$obsolete" snapshots restore || exit 1
  >   reject "$obsolete" snapshots import-resurrect tmux_resurrect_20260720T213239.txt || exit 1
  >   reject "$obsolete" snapshots prune || exit 1
  >   reject "$obsolete" service sync --source /bin/sh || exit 1
  >   reject "$obsolete" service rollback || exit 1
  >   reject "$obsolete" service enable || exit 1
  >   reject "$obsolete" service disable || exit 1
  >   reject "$obsolete" autonomy configure --mode live || exit 1
  >   reject "$obsolete" autonomy tick || exit 1
  >   reject "$obsolete" autonomy cancel missing-action || exit 1
  >   reject "$obsolete" autonomy pause || exit 1
  >   reject "$obsolete" autonomy resume || exit 1
  > done
  $ reject --apply snapshots prune
  $ test ! -e "$XDG_DATA_HOME/tmux-recovery"
  $ test ! -e "$XDG_STATE_HOME/tmux-recovery"
  $ test ! -e "$XDG_CONFIG_HOME/tmux-recovery"
  $ test ! -e "$XDG_RUNTIME_DIR/tmux-recovery"

The old autonomy mode spellings are rejected before policy creation.

  $ for mode in dry-run dry_run dryrun; do
  >   if ../../bin/headless.exe autonomy configure --mode "$mode" > rejected.txt 2>&1; then echo "unexpectedly accepted $mode"; exit 1; fi
  > done
  $ test ! -e "$XDG_CONFIG_HOME/tmux-recovery"

Plain sync writes the runtime and updates the current pointer.

  $ ../../bin/headless.exe service sync --source /bin/sh --json > sync.json
  $ sed -n '/"applied":/p' sync.json
      "applied": true,
  $ test -L "$runtime/current"
  $ test -x "$runtime/current/tmux-recovery"
  $ cmp /bin/sh "$runtime/current/tmux-recovery"

Rollback also executes directly, swapping the current and previous pointers.

  $ original=$(readlink "$runtime/current")
  $ mkdir "$runtime/fixture-previous"
  $ cp /bin/sh "$runtime/fixture-previous/tmux-recovery"
  $ ln -s fixture-previous "$runtime/previous"
  $ ../../bin/headless.exe service rollback
  Rolled the stable runtime back to the previous version.
  $ readlink "$runtime/current"
  fixture-previous
  $ test "$(readlink "$runtime/previous")" = "$original"
  $ ../../bin/headless.exe service sync --source /bin/sh --json > sync.json
  $ test "$(readlink "$runtime/current")" = "$original"

Live autonomy can be configured directly; configuration never runs a tick.
Threshold-only updates preserve the selected mode and update the saved policy.

  $ ../../bin/headless.exe autonomy configure --mode live --grace 120 --persistence 60 --snapshot-before-fire false
  autonomy policy updated (mode: live)
  $ ../../bin/headless.exe autonomy configure --grace 180
  autonomy policy updated (mode: live)
  $ ../../bin/headless.exe autonomy status --json > autonomy.json
  $ sed -n '/"mode":/p; /"grace_seconds":/p; /"persistence_seconds":/p; /"snapshot_before_fire":/p' autonomy.json
        "mode": "live",
        "grace_seconds": 180,
        "persistence_seconds": 60,
        "snapshot_before_fire": false
  $ ../../bin/headless.exe autonomy configure --mode off
  autonomy policy updated (mode: off)

Import commits a native snapshot immediately. A saved command is data and must
never execute during import. Retention then deletes an eligible old bundle while
preserving an old last-good pointer and the latest snapshot.

  $ mkdir legacy
  $ printf 'pane\twork\t0\t1\t:*\t0\tshell\t:/tmp\t1\tsh\t:touch %s/import-command-ran\nwindow\twork\t0\t:main\t1\t:*\tlayout\ton\nstate\twork\twork\n' "$PWD" > legacy/tmux_resurrect_20260720T213239.txt
  $ native="$PWD/imported"
  $ ../../bin/headless.exe snapshots import-resurrect tmux_resurrect_20260720T213239.txt --directory "$PWD/legacy" --native-directory "$native" --json > import.json
  $ test -f "$native/latest/snapshot.json"
  $ test ! -e import-command-ran
  $ first=$(readlink "$native/latest")
  $ ../../bin/headless.exe snapshots import-resurrect tmux_resurrect_20260720T213239.txt --directory "$PWD/legacy" --native-directory "$native" --json > import.json
  $ second=$(readlink "$native/latest")
  $ for n in 3 4 5 6 7 8 9 10 11 12; do ../../bin/headless.exe snapshots import-resurrect tmux_resurrect_20260720T213239.txt --directory "$PWD/legacy" --native-directory "$native" --json > import.json || exit 1; done
  $ rm "$native/last-good"
  $ ln -s "$first" "$native/last-good"
  $ ../../bin/headless.exe snapshots prune --native-directory "$native" --json > prune.json
  $ sed -n '/"applied":/p' prune.json
      "applied": true,
  $ test -d "$native/$first"
  $ test ! -e "$native/$second"
  $ test -f "$native/latest/snapshot.json"
  $ test -f "$native/last-good/snapshot.json"
  $ test ! -e import-command-ran
