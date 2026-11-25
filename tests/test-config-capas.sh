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

# Defaults de observabilidad: TRIO_STALE_MINUTES=15 y TRIO_QUOTA_PATTERNS no vacío,
# sobrescribibles desde trio.conf.
grep -qE '^TRIO_STALE_MINUTES="?15"?' "$aqui/trio.conf.example" \
  || fallo "trio.conf.example debe definir TRIO_STALE_MINUTES=15"
grep -qE '^TRIO_QUOTA_PATTERNS=' "$aqui/trio.conf.example" \
  || fallo "trio.conf.example debe definir TRIO_QUOTA_PATTERNS"

bash -c '
  set -euo pipefail
  TRIO_ROOT="'"$aqui"'"
  TRIO_SHARE_DIR="'"$tmp/share"'"
  TRIO_OVERRIDE_DIR="'"$tmp/zt"'"
  project_dir="'"$tmp/pj-demo"'"
  source "'"$aqui"'/runtime/lib/trio_config.sh"
  trio_cargar_config
  [[ "$TRIO_STALE_MINUTES" == "15" ]] || { echo "esperaba TRIO_STALE_MINUTES=15, dio $TRIO_STALE_MINUTES" >&2; exit 1; }
  [[ -n "$TRIO_QUOTA_PATTERNS" ]] || { echo "esperaba TRIO_QUOTA_PATTERNS no vacío" >&2; exit 1; }
  grep -iEq "$TRIO_QUOTA_PATTERNS" <<<"Error 429: rate limit exceeded" || { echo "TRIO_QUOTA_PATTERNS debe detectar rate limit/429" >&2; exit 1; }
  printf "TRIO_STALE_MINUTES=30\nTRIO_QUOTA_PATTERNS=\"mi-cuota\"\n" > "$project_dir/.trio/trio.conf"
  trio_cargar_config
  [[ "$TRIO_STALE_MINUTES" == "30" ]] || { echo "repo no sobrescribió TRIO_STALE_MINUTES: $TRIO_STALE_MINUTES" >&2; exit 1; }
  [[ "$TRIO_QUOTA_PATTERNS" == "mi-cuota" ]] || { echo "repo no sobrescribió TRIO_QUOTA_PATTERNS: $TRIO_QUOTA_PATTERNS" >&2; exit 1; }
' || fallo "falló verificación de TRIO_STALE_MINUTES / TRIO_QUOTA_PATTERNS en trio_cargar_config"

echo "OK config por capas"
