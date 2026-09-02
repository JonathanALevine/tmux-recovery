#!/usr/bin/env bash
# Verify that the CLI's declared version matches the expected version.
#
# Usage:
#   scripts/check-version.sh <expected-version>
#
# The release workflow passes the target version (e.g. "0.3.0") and this
# script fails if lib/cli/cli.ml declares anything else. This keeps the
# `--version` output, the opam package, and the git tag in lockstep.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <expected-version>" >&2
  exit 2
fi

expected="$1"
cli_file="lib/cli/cli.ml"

if [[ ! -f "$cli_file" ]]; then
  echo "error: $cli_file not found" >&2
  exit 1
fi

cli_version="$(
  grep -oE 'let[[:space:]]+version[[:space:]]*=[[:space:]]*"[^"]*"' "$cli_file" \
    | head -n1 \
    | sed -E 's/.*"([^"]*)".*/\1/'
)"

if [[ -z "$cli_version" ]]; then
  echo "error: could not extract the CLI version from $cli_file" >&2
  exit 1
fi

if [[ "$cli_version" != "$expected" ]]; then
  echo "version mismatch: $cli_file declares '$cli_version' but '$expected' was expected" >&2
  exit 1
fi

echo "version OK: $cli_version"
