Service sync previews are optional and do not create a runtime directory.

  $ export XDG_DATA_HOME="$PWD/data"
  $ export XDG_STATE_HOME="$PWD/state"
  $ runtime="$XDG_DATA_HOME/tmux-recovery/bin"
  $ ../../bin/headless.exe service sync --source /bin/sh --dry-run --json > preview.json
  $ sed -n '/"applied":/p' preview.json
      "applied": false,
  $ test ! -e "$runtime"

Older scripts can still pass --approve, and --dry-run always takes precedence.

  $ ../../bin/headless.exe service sync --source /bin/sh --approve --dry-run --json > preview.json
  $ sed -n '/"applied":/p' preview.json
      "applied": false,
  $ test ! -e "$runtime"

Plain sync writes the runtime and updates the current pointer without approval.

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

The compatibility flag still permits execution in older scripts.

  $ ../../bin/headless.exe service sync --source /bin/sh --approve --json > sync.json
  $ sed -n '/"applied":/p' sync.json
      "applied": true,
  $ test "$(readlink "$runtime/current")" = "$original"
