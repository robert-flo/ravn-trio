#!/usr/bin/env bash
# Pruebas de --ticket-repo <owner/repo>: separa ISSUE_REPO de PR_REPO.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export TRIO_SHARE_DIR="$tmp/noexiste"
export PATH="/usr/bin:/bin"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q -b main "$tmp/HR-CLAVIS"
git -C "$tmp/HR-CLAVIS" remote add origin "https://github.com/robert-flo/HR-CLAVIS.git"
git init -q -b main "$tmp/miembro"
git -C "$tmp/miembro" remote add origin "https://github.com/robert-flo/miembro.git"

# 1. Con --repo miembro --ticket-repo robert-flo/HR-CLAVIS (PM y kickoff)
k="$("$aqui/pj-trio" --print-kickoff "$tmp/HR-CLAVIS" 98 --repo "$tmp/miembro" --ticket-repo robert-flo/HR-CLAVIS)"
grep -q '{{' <<<"$k" && fallo "quedan placeholders en PM kickoff con --ticket-repo"
grep -qF 'gh issue view 98 -R robert-flo/HR-CLAVIS --comments' <<<"$k" || fallo "falta -R robert-flo/HR-CLAVIS en gh issue view"
grep -qF 'gh pr create -R robert-flo/miembro' <<<"$k" || fallo "falta -R robert-flo/miembro en gh pr create"
grep -qF 'gh pr merge <pr> -R robert-flo/miembro' <<<"$k" || fallo "falta -R robert-flo/miembro en gh pr merge"
grep -qF 'gh pr view <pr> -R robert-flo/miembro' <<<"$k" || fallo "falta -R robert-flo/miembro en gh pr view"
grep -qF 'gh issue edit 98 -R robert-flo/HR-CLAVIS' <<<"$k" || fallo "falta -R robert-flo/HR-CLAVIS en gh issue edit"
grep -qF 'robert-flo/HR-CLAVIS#98' <<<"$k" || fallo "falta referencia robert-flo/HR-CLAVIS#98 en encargo al WK"

# 2. Subcomando kickoff con --ticket-repo= y --oneshot
ko="$("$aqui/pj-trio" kickoff "$tmp/HR-CLAVIS" 98 --repo "$tmp/miembro" --ticket-repo=robert-flo/HR-CLAVIS --oneshot)"
grep -q '{{' <<<"$ko" && fallo "quedan placeholders en OS kickoff con --ticket-repo"
grep -qF 'gh issue view 98 -R robert-flo/HR-CLAVIS --comments' <<<"$ko" || fallo "OS: falta -R robert-flo/HR-CLAVIS en gh issue view"
grep -qF 'gh pr create -R robert-flo/miembro' <<<"$ko" || fallo "OS: falta -R robert-flo/miembro en gh pr create"
grep -qF 'gh pr merge <pr> -R robert-flo/miembro' <<<"$ko" || fallo "OS: falta -R robert-flo/miembro en gh pr merge"
grep -qF 'robert-flo/HR-CLAVIS#98' <<<"$ko" || fallo "OS: falta referencia robert-flo/HR-CLAVIS#98"

# 3. --dry-run con --ticket-repo
dry="$("$aqui/pj-trio" --dry-run "$tmp/HR-CLAVIS" 98 --repo "$tmp/miembro" --ticket-repo robert-flo/HR-CLAVIS 2>&1)"
grep -qF 'robert-flo/HR-CLAVIS' <<<"$dry" || fallo "dry-run no muestra issue repo"
grep -qF 'robert-flo/miembro' <<<"$dry" || fallo "dry-run no muestra PR repo"

# 4. Retrocompatibilidad: sin --ticket-repo, ISSUE_REPO == PR_REPO
k_compat="$("$aqui/pj-trio" --print-kickoff "$tmp/HR-CLAVIS" 42 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k_compat" && fallo "quedan placeholders sin --ticket-repo"
grep -qF 'gh issue view 42 -R robert-flo/miembro --comments' <<<"$k_compat" || fallo "compat: issue view debe usar robert-flo/miembro"
grep -qF 'gh pr create -R robert-flo/miembro' <<<"$k_compat" || fallo "compat: pr create debe usar robert-flo/miembro"
grep -qF 'gh pr merge <pr> -R robert-flo/miembro' <<<"$k_compat" || fallo "compat: pr merge debe usar robert-flo/miembro"

# 5. Caso negativo: --ticket-repo inválido falla rápido sin tocar disco, herdr ni red
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "herdr $*" >> "%s/calls.log"\n' "$tmp" > "$tmp/bin/herdr"
printf '#!/bin/sh\necho "gh $*" >> "%s/calls.log"\n' "$tmp" > "$tmp/bin/gh"
chmod +x "$tmp/bin/herdr" "$tmp/bin/gh"

# shellcheck disable=SC2016 # literales a propósito: no deben expandirse.
for mala in 'solo-nombre' 'owner/repo/extra' '/repo' 'owner/' 'owner/repo con espacio' 'owner/repo$x' ''; do
  rm -f "$tmp/calls.log"
  if out="$(PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$tmp/no-existe" 98 --ticket-repo "$mala" 2>&1)"; then
    fallo "aceptó --ticket-repo '$mala'"
  fi
  grep -q -- '--ticket-repo' <<<"$out" || fallo "--ticket-repo '$mala' sin error claro: $out"
  [[ ! -e "$tmp/calls.log" ]] || fallo "llamó a herdr/gh con --ticket-repo inválido '$mala': $(cat "$tmp/calls.log")"
done

if PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$tmp/no-existe" 98 --ticket-repo >/dev/null 2>&1; then
  fallo "aceptó --ticket-repo sin valor"
fi

echo "OK ticket-repo"
