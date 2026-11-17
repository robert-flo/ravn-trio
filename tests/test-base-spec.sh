#!/usr/bin/env bash
# --base: un sub-issue sale de la rama de su spec (ADR 0006 de pj-template) y
# su PR va contra ella; sin --base (trivial), de origin/HEAD a la rama por defecto.
# La base se valida (allowlist + check-ref-format) y tiene que existir en origin.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PATH="/usr/bin:/bin"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Remote bare local con main y la rama del spec; el miembro lo tiene como origin.
git init -q --bare -b main "$tmp/remoto.git"
git init -q -b main "$tmp/miembro"
git -C "$tmp/miembro" commit -q --allow-empty -m inicio
git -C "$tmp/miembro" remote add origin "$tmp/remoto.git"
git -C "$tmp/miembro" push -q origin main main:spec/12-login
git init -q "$tmp/pj-demo"

kickoff() { "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro" "$@"; }

# Trivial: origin/HEAD, PR a la rama por defecto y gh pr create sin --base.
k="$(kickoff)"
grep -q '{{' <<<"$k" && fallo "quedan placeholders sin --base"
grep -qE "git-create-worktree -r [^ ]+/miembro -B 'origin/HEAD' -b issue/42-<slug> -p '' 42-<slug>\`" <<<"$k" \
  || fallo "sin --base el worktree debería salir de 'origin/HEAD'"
grep -q 'worktree add -b' <<<"$k" && fallo "queda git worktree add a mano"
grep -q '^4\. (Trivial o PR final) Mandale la revisión a RV' <<<"$k" || fallo "un trivial pasa por RV"
grep -q 'mergeá vos tu PR' <<<"$k" && fallo "en un trivial el WK no mergea"
grep -q 'abrí el PR contra la rama por defecto con: gh pr create -R [^ ]* (más' <<<"$k" \
  || fallo "sin --base, gh pr create explícito y sin --base"

# Sub-issue: origin/<rama del spec>, PR contra ella con gh pr create --base.
for arg in "--base spec/12-login" "--base origin/spec/12-login" "--base=spec/12-login"; do
  # shellcheck disable=SC2086 # arg lleva opción y valor a propósito.
  k="$(kickoff $arg)"
  grep -q '{{' <<<"$k" && fallo "quedan placeholders con $arg"
  grep -qE "git-create-worktree -r [^ ]+/miembro -B 'origin/spec/12-login' -b issue/42-<slug> -p '' 42-<slug>\`" <<<"$k" \
    || fallo "con $arg el worktree debería salir de 'origin/spec/12-login'"
  grep -q 'Es un sub-issue: con CI verde y code-review limpio, mergeá vos tu PR a spec/12-login con gh pr merge <pr> -R [^ ]* --squash --delete-branch --match-head-commit <sha-verde>' <<<"$k" \
    || fallo "con $arg el WK debería mergear su sub-issue a la rama del spec"
  grep -q 'no hay paso RV ni merge tuyo' <<<"$k" || fallo "con $arg el PM no debería pasar el sub-issue por RV"
  grep -q "abrí el PR contra spec/12-login con: gh pr create -R [^ ]* --base 'spec/12-login'" <<<"$k" \
    || fallo "con $arg falta gh pr create --base 'spec/12-login'"
  grep -q 'origin/origin/' <<<"$k" && fallo "con $arg quedó origin/origin/"
done

# El dry-run muestra la base.
out="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 42 --repo "$tmp/miembro" --base spec/12-login 2>&1)"
grep -q 'Base del worktree y del PR: origin/spec/12-login' <<<"$out" || fallo "dry-run sin la base"

# Rechazos: inyección de shell, & (rompe el render), -x, .., @ y --base sin valor.
# shellcheck disable=SC2016 # literales a propósito: no deben expandirse.
for mala in 'spec/$(touch${IFS}/tmp/pwn)' 'spec/x;id' 'spec/`id`' 'spec/a|b' 'spec/a&b' "spec/a'b" '-x' 'a..b' '@' 'spec/@{-1}'; do
  if out="$(kickoff --base "$mala" 2>&1)"; then fallo "aceptó --base '$mala'"; fi
  grep -q 'no es un nombre de rama válido' <<<"$out" || fallo "--base '$mala' sin error claro: $out"
done
if kickoff --base >/dev/null 2>&1; then fallo "aceptó --base sin valor"; fi

# Rama inexistente en origin: falla antes de abrir tabs (herdr de mentira que anota llamadas).
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "$@" >> "%s/herdr.log"\n' "$tmp" > "$tmp/bin/herdr"
chmod +x "$tmp/bin/herdr"
if out="$(PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$tmp/pj-demo" 42 --repo "$tmp/miembro" --base spec/nope 2>&1)"; then
  fallo "aceptó una rama que no existe en origin"
fi
grep -q "la rama 'spec/nope' no existe en origin" <<<"$out" || fallo "rama inexistente sin error claro: $out"
[[ ! -e "$tmp/herdr.log" ]] || fallo "llamó a herdr antes de validar la base: $(cat "$tmp/herdr.log")"
if kickoff --base spec/nope >/dev/null 2>&1; then fallo "--print-kickoff aceptó una rama inexistente"; fi

# Ref exacta: «12-login» no existe aunque origin tenga spec/12-login (ls-remote --heads matchea el final).
rm -f "$tmp/herdr.log"
if out="$(PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$tmp/pj-demo" 42 --repo "$tmp/miembro" --base 12-login 2>&1)"; then
  fallo "aceptó --base 12-login con solo spec/12-login en origin"
fi
grep -q "la rama '12-login' no existe en origin" <<<"$out" || fallo "--base 12-login sin error claro: $out"
[[ ! -e "$tmp/herdr.log" ]] || fallo "llamó a herdr antes de validar la base: $(cat "$tmp/herdr.log")"

echo "OK base del spec"
