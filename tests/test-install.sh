#!/usr/bin/env bash
# make install DESTDIR: layout que pj-trio espera.
set -euo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT
make -s -C "$raiz" DESTDIR="$dest" install
test -x "$dest/usr/bin/pj-trio"
test -x "$dest/usr/share/ravn/trio/trio-status"
test -f "$dest/usr/share/ravn/trio/trio-pm-prompt.md"
test -f "$dest/usr/share/ravn/trio/trio.conf.example"
echo "OK"
