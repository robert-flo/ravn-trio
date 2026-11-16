#!/usr/bin/env bash
# --base: un sub-issue sale de la rama de su spec (ADR 0006 de pj-template) y
# su PR va contra ella; sin --base (trivial), de origin/HEAD a la rama por defecto.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

git init -q "$tmp/pj-demo"
git init -q "$tmp/miembro"
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PATH="/usr/bin:/bin"

# Trivial: origin/HEAD y PR a la rama por defecto.
k="$("$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k" && fallo "quedan placeholders sin --base"
grep -qE 'worktree add -b feat/42-<slug> .*/miembro-wt-42-\$\(date \+%Y%m%d%H%M%S\) origin/HEAD`' <<<"$k" \
  || fallo "sin --base el worktree debería salir de origin/HEAD"
grep -q 'abrí el PR contra la rama por defecto' <<<"$k" || fallo "sin --base el PR va a la rama por defecto"

# Sub-issue: origin/<rama del spec> y PR contra ella (también con prefijo origin/ y con =).
for arg in "--base spec/12-login" "--base origin/spec/12-login" "--base=spec/12-login"; do
  # shellcheck disable=SC2086 # arg lleva opción y valor a propósito.
  k="$("$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro" $arg)"
  grep -q '{{' <<<"$k" && fallo "quedan placeholders con $arg"
  grep -qE 'worktree add -b feat/42-<slug> .*/miembro-wt-42-\$\(date \+%Y%m%d%H%M%S\) origin/spec/12-login`' <<<"$k" \
    || fallo "con $arg el worktree debería salir de origin/spec/12-login"
  grep -q 'abrí el PR contra spec/12-login' <<<"$k" || fallo "con $arg el PR va contra la rama del spec"
  grep -q 'origin/origin/' <<<"$k" && fallo "con $arg quedó origin/origin/"
done

# El dry-run muestra la base.
out="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 42 --repo "$tmp/miembro" --base spec/12-login 2>&1)"
grep -q 'Base del worktree y del PR: origin/spec/12-login' <<<"$out" || fallo "dry-run sin la base"

# Nombre de rama inválido o --base sin valor: error.
if "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --base 'mal..rama' >/dev/null 2>&1; then fallo "aceptó una rama inválida"; fi
if "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --base >/dev/null 2>&1; then fallo "aceptó --base sin valor"; fi

echo "OK base del spec"
