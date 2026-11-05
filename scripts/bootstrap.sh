#!/bin/sh
# bootstrap.sh
#
# Turns on this repository's git hooks after a fresh clone, and checks that the
# tools the hooks need are installed. `core.hooksPath` is per-clone git config
# and cannot be committed, so this has to be run once per clone. Safe to re-run.
set -eu

cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks
echo "bootstrap: git hooks enabled (core.hooksPath = .githooks)"

missing=0
for tool in swift quality-gate; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "bootstrap: found $tool"
  else
    echo "bootstrap: $tool is not on the PATH; the hooks need it and will refuse to run without it" >&2
    missing=1
  fi
done

exit "$missing"
