#!/usr/bin/env bash
# Regla de merge: el PM nunca mergea; tras APRUEBO queda needs-roberto esperando la orden de Roberto.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fallo() { echo "FALLO: $*" >&2; exit 1; }

prompt="$aqui/trio-pm-prompt.md"
readme="$aqui/README.md"

# En ningún archivo hay una instrucción de merge ejecutado por el PM.
if grep -qiE 'mergeá vos|mergea vos|mergeá tú|el PM mergea' "$prompt" "$readme"; then
  fallo "hay una instrucción de merge ejecutado por el PM"
fi

# El comando gh pr merge solo aparece como acción de Roberto.
while IFS= read -r linea; do
  grep -q 'Roberto' <<<"$linea" || fallo "gh pr merge sin la orden de Roberto: $linea"
done < <(grep -h 'gh pr merge' "$prompt" "$readme")

# Paso 6: APRUEBO → needs-roberto con --pr y --head, y el head no cambia.
paso6="$(grep -A4 'Si RV dice APRUEBO' "$prompt")"
grep -q 'needs-roberto merge' <<<"$paso6" || fallo "APRUEBO debería dejar needs-roberto merge"
grep -q -- '--pr' <<<"$paso6" || fallo "needs-roberto debería llevar --pr"
grep -q -- '--head' <<<"$paso6" || fallo "needs-roberto debería llevar --head"
grep -q 'no debe cambiar' <<<"$paso6" || fallo "falta la regla: el head no cambia después del APRUEBO"

# Paso 7: el cierre corre una vez que Roberto ordenó (o confirmó) el merge.
grep -q '^7\. Cuando Roberto ordenó' "$prompt" || fallo "el cierre debería correr después de la orden de Roberto"

# La regla también queda en Límites.
grep -q 'Nunca mergees un PR por tu cuenta' "$prompt" || fallo "falta la regla de merge en Límites"

echo "OK prompt del PM: merge solo Roberto"
