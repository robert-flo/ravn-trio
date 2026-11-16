#!/usr/bin/env bash
# Regla de merge (ADR 0014 de pj-template): tras APRUEBO <sha> de RV, el PM
# mergea con --match-head-commit <sha>; si el head cambió, no mergea y pide
# otra revisión; después avisa a Roberto.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fallo() { echo "FALLO: $*" >&2; exit 1; }

prompt="$aqui/trio-pm-prompt.md"
readme="$aqui/README.md"

# Ningún texto deja el merge en manos de Roberto.
if grep -qiE 'NO mergees: avisale|lo corre Roberto|solo Roberto|lo ejecuta Roberto|mergees un PR por tu cuenta' "$prompt" "$readme"; then
  fallo "queda una instrucción de merge solo por Roberto"
fi

# Todo gh pr merge lleva squash, delete-branch y match-head-commit.
while IFS= read -r linea; do
  for op in --squash --delete-branch '--match-head-commit <sha>'; do
    grep -qF -- "$op" <<<"$linea" || fallo "gh pr merge sin $op: $linea"
  done
done < <(grep -h 'gh pr merge' "$prompt" "$readme")

# Paso 6: APRUEBO → el PM mergea; si el head cambió, otra revisión.
paso6="$(grep -A4 '^6\. Si RV dice APRUEBO' "$prompt")"
grep -q 'mergeás vos' <<<"$paso6" || fallo "tras APRUEBO el PM debería mergear"
grep -q 'gh pr merge' <<<"$paso6" || fallo "falta el comando de merge en el paso 6"
grep -q 'NO mergees: volvé al paso 4' <<<"$paso6" || fallo "falta la regla: si el head cambió, otra revisión"

# Paso 7: cierre y aviso a Roberto con PR, APRUEBO, sha del merge y validación.
paso7="$(grep -A2 '^7\. Después del merge' "$prompt")"
for dato in 'link del PR' 'APRUEBO' 'sha del merge' 'validación manual'; do
  grep -q "$dato" <<<"$paso7" || fallo "el aviso a Roberto no lleva: $dato"
done

# El WK abre el PR con gh pr create explícito y la base del ticket.
grep -qF 'gh pr create -R {{TICKET_REPO}}{{GH_PR_BASE}}' "$prompt" || fallo "falta gh pr create con la base en el encargo al WK"

# El README también dice que con head nuevo no se mergea y que se avisa a Roberto.
grep -q 'Si el head cambió después del APRUEBO, no mergea y pide otra revisión' "$readme" || fallo "README sin la regla del head que cambió"
grep -q 'le avisa a Roberto con el link del PR, el link del APRUEBO, el sha del merge' "$readme" || fallo "README sin el aviso a Roberto"

# La regla también queda en Límites.
grep -qF 'Mergeás solo tras APRUEBO <sha>' "$prompt" || fallo "falta la regla de merge en Límites"

echo "OK prompt del PM: mergea tras APRUEBO sobre el head exacto"
