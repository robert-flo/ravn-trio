#!/usr/bin/env bash
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$TMPDIR"
export GIT_CONFIG_GLOBAL=/dev/null

echo "Running test suite in $tests_dir..."
for t in "$tests_dir"/test-*.sh; do
  echo "=== Running $(basename "$t") ==="
  bash "$t"
done
echo "All tests passed successfully!"
