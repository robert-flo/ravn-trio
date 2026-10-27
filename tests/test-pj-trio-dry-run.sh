#!/usr/bin/env bash
# Prueba sin herdr: --dry-run y --print-kickoff de pj-trio sobre repos temporales.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/pj-demo"
git init -q "$tmp/miembro"
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PATH="/usr/bin:/bin"

fallo() { echo "FALLO: $*" >&2; exit 1; }

out="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 42 --repo "$tmp/miembro" 2>&1)"
grep -q 'herdr agent start "pm-pj-demo-miembro-42"' <<<"$out" || fallo "nombre de agente por proyecto y ticket"
grep -q 'herdr agent prompt "pm-pj-demo-miembro-42"' <<<"$out" || fallo "envío del arranque"
out43="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 43 --repo "$tmp/miembro" 2>&1)"
grep -q 'herdr agent start "pm-pj-demo-miembro-43"' <<<"$out43" || fallo "otro ticket del mismo proyecto usa otro nombre"
grep -q "config user.email \"25asab015@ujmd.edu.sv\"" <<<"$out" || fallo "identidad git"
[[ ! -e "$tmp/pj-demo/.trio" ]] || fallo "--dry-run escribió .trio"
[[ -z "$(git -C "$tmp/pj-demo" config --local user.email || true)" ]] || fallo "--dry-run tocó git config"

k="$("$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k" && fallo "quedan placeholders"
grep -q "$tmp/pj-demo/.trio/miembro-42" <<<"$k" || fallo "carpeta de handoff"
grep -q 'herdr agent prompt wk-pj-demo-miembro-42' <<<"$k" || fallo "PM no pinguea a WK"
grep -q -- '--match-head-commit' <<<"$k" || fallo "merge sin match-head-commit"
grep -qi 'worktree add' <<<"$k" || fallo "worktree nuevo"

# Idempotencia del arranque: con status.json presente no se reenvía.
mkdir -p "$tmp/pj-demo/.trio/42" && echo '{}' > "$tmp/pj-demo/.trio/42/status.json"
out="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 42 2>&1)"
grep -q 'no se reenvía' <<<"$out" || fallo "reenvío del arranque"

grep -q 'needs-roberto' <<<"$k" || fallo "regla de fallo definitivo"
grep -q -- '--notify' <<<"$k" || fallo "aviso notify-send"
grep -qi 'UNA vez' <<<"$k" || fallo "reintento único"

# trio-status: esquema, conserva claves, dry-run sin escribir, notify con stub.
ts="$aqui/trio-status"
d="$tmp/pj-demo/.trio/43"
out="$("$ts" --dry-run --notify "$d" needs-roberto wk --error x 2>&1)"
grep -q 'notify-send' <<<"$out" || fallo "dry-run sin notify-send"
[[ ! -e "$d" ]] || fallo "trio-status --dry-run escribió"
"$ts" "$d" en-curso wk --pr https://e/pr/1 --head abc
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "$@" > "%s/notificado"\n' "$tmp" > "$tmp/bin/notify-send"
chmod +x "$tmp/bin/notify-send"
PATH="$tmp/bin:$PATH" "$ts" --notify "$d" needs-roberto wk --intentos 2 --error "wk ausente"
jq -e '.estado=="needs-roberto" and .paso=="wk" and .error=="wk ausente" and .intentos==2
    and .pr=="https://e/pr/1" and .head=="abc" and .ticket=="43" and (.timestamp|length>0)' \
    "$d/status.json" >/dev/null || fallo "esquema de status.json"
grep -q 'needs-roberto' "$tmp/notificado" || fallo "notify-send no se llamó"
if "$ts" "$d" raro wk 2>/dev/null; then fallo "aceptó estado inválido"; fi

echo "OK"
