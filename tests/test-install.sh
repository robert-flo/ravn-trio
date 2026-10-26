#!/usr/bin/env bash
# make install DESTDIR: layout que pj-trio espera.
set -euo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT
make -s -C "$raiz" DESTDIR="$dest" install
test -L "$dest/usr/bin/pj-trio"
test -x "$dest/usr/share/ravn/trio/runtime/scripts/start"
# El launcher instalado funciona fuera del checkout.
"$dest/usr/share/ravn/trio/pj-trio" help >/dev/null
test -x "$dest/usr/share/ravn/trio/trio-status"
test -f "$dest/usr/share/ravn/trio/trio-pm-prompt.md"
test -f "$dest/usr/share/ravn/trio/trio.conf.example"
echo "OK"
