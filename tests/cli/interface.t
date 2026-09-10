The public command tree keeps the everyday commands and inspection tools.
Neither removed subcommand is accepted, including by the full TUI executable.

  $ for binary in ../../bin/headless.exe ../../bin/main.exe; do
  >   for removed in ui migrate; do
  >     if "$binary" "$removed" > rejected.txt 2>&1; then echo "unexpectedly accepted $removed"; exit 1; fi
  >     grep -F "unknown subcommand $removed" rejected.txt > /dev/null || exit 1
  >   done
  > done
  $ ../../bin/main.exe help -recursive -flags -expand-dots > help.txt
  $ if grep -E -- '--dry-run|--approve|--apply|(^|[[:space:]])ui[[:space:]]|(^|[[:space:]])migrate[[:space:]]' help.txt; then exit 1; fi
  $ COMP_CWORD=1 ../../bin/main.exe ''
  autonomy
  completion
  doctor
  help
  processes
  restore
  service
  snapshot
  snapshots
  status
  tree
  version

The implicit TUI also accepts and completes its named-socket option.

  $ COMP_CWORD=1 ../../bin/main.exe '--s'
  --socket
  $ ../../bin/main.exe --socket fixture --help > tui-help.txt
  $ grep -F -- '--socket' tui-help.txt > /dev/null

Bash and zsh use the same dynamic command parser. Completion for actions and
aliases must advertise the useful options without any removed execution gates.

  $ ../../bin/main.exe completion bash > bash-completion.txt
  $ ../../bin/main.exe completion zsh > zsh-completion.txt
  $ grep -F 'COMP_CWORD' bash-completion.txt > /dev/null
  $ grep -F 'COMP_CWORD' zsh-completion.txt > /dev/null
  $ COMP_CWORD=2 ../../bin/main.exe snapshot '' > snapshot-completion.txt
  $ COMP_CWORD=2 ../../bin/main.exe restore '' > restore-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe snapshots save '' > save-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe snapshots restore '' > grouped-restore-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe snapshots prune '' > prune-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe snapshots import-resurrect '' > import-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe service sync '' > sync-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe service enable '' > enable-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe service disable '' > disable-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe service rollback '' > rollback-completion.txt
  $ COMP_CWORD=3 ../../bin/main.exe autonomy configure '' > configure-completion.txt
  $ if grep -E -- '--dry-run|--approve|--apply' *-completion.txt; then exit 1; fi

With no interactive terminal, bare invocation shows help and exits successfully.

  $ ../../bin/main.exe < /dev/null > bare.txt
  $ grep -F 'subcommands' bare.txt > /dev/null
