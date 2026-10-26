#!/usr/bin/env bash
# Plugin de herdr: manifiesto válido y acción new-trio deduce proyecto y ticket del contexto.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

python3 - "$aqui/herdr-plugin.toml" <<'PY'
import sys, tomllib
m = tomllib.load(open(sys.argv[1], "rb"))
for k in ("id", "name", "version", "min_herdr_version"):
    assert m.get(k), k
acts = {a["id"]: a for a in m["actions"]}
assert acts["new-trio"]["title"] == "New trio"
assert all(h["action"] in acts for h in m.get("link_handlers", []))
PY

git init -q "$tmp/pj-demo"; mkdir -p "$tmp/pj-demo/sub"
export PJ_TRIO_CONFIG="$aqui/trio.conf.example" PJ_TRIO_PLUGIN_ARGS="--dry-run" PATH="/usr/bin:/bin"
export HERDR_PLUGIN_ROOT="$aqui"

out="$(HERDR_PLUGIN_CONTEXT_JSON="{\"pane\":{\"cwd\":\"$tmp/pj-demo/sub\"},\"clicked_url\":\"https://github.com/robert-flo/pj-demo/issues/42\"}" "$aqui/runtime/plugin/new-trio" 2>&1)"
grep -q 'pm-pj-demo-42' <<<"$out" || fallo "ticket desde la URL y proyecto desde el cwd del panel"

out="$(HERDR_PLUGIN_CONTEXT_JSON="{\"worktree\":{\"path\":\"$tmp/pj-demo\"},\"selected_text\":\" #9 \"}" "$aqui/runtime/plugin/new-trio" 2>&1)"
grep -q 'pm-pj-demo-9' <<<"$out" || fallo "ticket desde la selección"

if HERDR_PLUGIN_CONTEXT_JSON="{\"pane\":{\"cwd\":\"$tmp/pj-demo\"}}" "$aqui/runtime/plugin/new-trio" >/dev/null 2>&1; then
    fallo "sin ticket debe fallar"
fi
echo "OK plugin"
