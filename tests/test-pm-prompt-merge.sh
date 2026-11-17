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

# Paso 6: APRUEBO → el PM evalúa Merge Danger y mergea o pide merge humano; si el head cambió, otra revisión.
paso6="$(sed -n '/^6\. Si RV dice APRUEBO/,/^7\. Después del merge/p' "$prompt")"
grep -q 'mergeás vos' <<<"$paso6" || fallo "tras APRUEBO el PM debería mergear"
grep -q 'gh pr merge' <<<"$paso6" || fallo "falta el comando de merge en el paso 6"
grep -q 'NO mergees: volvé al paso 4' <<<"$paso6" || fallo "falta la regla: si el head cambió, otra revisión"
grep -qF 'gh pr view <pr> -R {{TICKET_REPO}} --json body -q .body' <<<"$paso6" || fallo "falta lectura de body del PR para Merge Danger"
grep -q 'Door: two-way' <<<"$paso6" || fallo "falta condición Door: two-way"
grep -q 'Blast Radius: Low' <<<"$paso6" || fallo "falta condición Blast Radius: Low"
grep -qi 'case-insensitive' <<<"$paso6" || fallo "falta aclaración case-insensitive"
grep -qF 'ready-to-merge' <<<"$paso6" || fallo "falta fallback a etiqueta ready-to-merge"
grep -qF 'needs-roberto' <<<"$paso6" || fallo "falta fallback a needs-roberto"
grep -qF -- '--merge-danger' <<<"$paso6" || fallo "falta --merge-danger en fallback"
grep -q 'ready-for-agent' <<<"$paso6" || fallo "falta limpieza de etiquetas ready-for-agent/needs-*"

# Paso 7: cierre, notificación, worktree remove y herdr workspace close al final.
paso7="$(sed -n '/^7\. Después del merge/,/^## /p' "$prompt")"
for dato in 'link del PR' 'APRUEBO' 'sha del merge' 'validación manual' 'herdr workspace list' 'herdr workspace close' '{{WORKSPACE_NOMBRE}}'; do
  grep -qF "$dato" <<<"$paso7" || fallo "el paso 7 no lleva: $dato"
done

# Sustitución de {{WORKSPACE_NOMBRE}} en pj-trio --print-kickoff.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/pj-demo"
git init -q "$tmp/miembro"
k="$(PJ_TRIO_CONFIG="$aqui/trio.conf.example" TRIO_SHARE_DIR="$tmp/noexiste" "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k" && fallo "quedan placeholders sin sustituir en kickoff"
grep -qF 'trio pj-demo/miembro#42' <<<"$k" || fallo "{{WORKSPACE_NOMBRE}} no se sustituyó en kickoff"

# Versión en herdr-plugin.toml.
grep -qFx 'version = "0.1.10"' "$aqui/herdr-plugin.toml" || fallo "herdr-plugin.toml debe estar en version = \"0.1.10\""

# El WK abre el PR con gh pr create explícito y la base del ticket.
grep -qF 'gh pr create -R {{TICKET_REPO}}{{GH_PR_BASE}}' "$prompt" || fallo "falta gh pr create con la base en el encargo al WK"

# El README también dice que con head nuevo no se mergea y que se avisa a Roberto.
grep -q 'Si el head cambió después del APRUEBO, no mergea y pide otra revisión' "$readme" || fallo "README sin la regla del head que cambió"
grep -q 'le avisa a Roberto con el link del PR, el link del APRUEBO, el sha del merge' "$readme" || fallo "README sin el aviso a Roberto"

# La regla también queda en Límites.
grep -qF 'Mergeás solo tras APRUEBO <sha>' "$prompt" || fallo "falta la regla de merge en Límites"

echo "OK prompt del PM: mergea tras APRUEBO sobre el head exacto"
