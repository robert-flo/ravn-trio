#!/usr/bin/env bash
# Config por capas: defaults → override en /zt → repo (la última gana); PJ_TRIO_CONFIG las reemplaza.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

git init -q "$tmp/pj-demo"
mkdir -p "$tmp/zt" "$tmp/share" "$tmp/pj-demo/.trio"
export TRIO_SHARE_DIR="$tmp/share" TRIO_OVERRIDE_DIR="$tmp/zt" PATH="/usr/bin:/bin"
unset PJ_TRIO_CONFIG

kinds() { "$aqui/pj-trio" --dry-run "$tmp/pj-demo" 7 2>&1; }

out="$(kinds)"
grep -q "trio.conf.example" <<<"$out" || fallo "sin capas usa trio.conf.example"

echo 'WK_KIND="kind-zt"' >"$tmp/zt/trio.conf"
grep -q 'kind-zt' <<<"$(kinds)" || fallo "el override en /zt pisa los defaults"

printf 'WK_KIND="kind-repo"\n' >"$tmp/pj-demo/.trio/trio.conf"
out="$(kinds)"
grep -q 'kind-repo' <<<"$out" || fallo "el repo pisa al override"
! grep -q 'kind-zt' <<<"$out" || fallo "quedó el kind del override"
grep -q "Configuración (capas.*$tmp/zt/trio.conf.*$tmp/pj-demo/.trio/trio.conf" <<<"$out" || fallo "orden de capas en dry-run"

echo 'WK_KIND="kind-env"' >"$tmp/env.conf"
grep -q 'kind-env' <<<"$(PJ_TRIO_CONFIG="$tmp/env.conf" kinds)" || fallo "PJ_TRIO_CONFIG reemplaza las capas"
echo "OK config por capas"
