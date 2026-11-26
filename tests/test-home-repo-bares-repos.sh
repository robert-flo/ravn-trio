#!/usr/bin/env bash
# Prueba de resolución centralizada de .bare/ y repos/ (ADR 0027).
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export PJ_TRIO_OS_PROMPT="$aqui/trio-os-prompt.md"
export PATH="/usr/bin:/bin"

fallo() { echo "FALLO: $*" >&2; exit 1; }

central="$tmp/central"
export RAVN_HOME_REPOS_ROOT="$central"
mkdir -p "$central/.bare" "$central/repos"

# 1. Home Repo sin el bare del miembro aún:
#    resuelve BARE_HOME y WORKTREES_HOME a la raíz central única y usa ravn-wt clone.
hr="$tmp/HR-DEMO"
mkdir -p "$hr/miembro"
git init -q "$hr"
git -C "$hr" remote add origin "https://github.com/robert-flo/HR-DEMO.git"
git init -q "$hr/miembro"
git -C "$hr/miembro" remote add origin "https://github.com/robert-flo/miembro.git"

for mode in "" "--oneshot"; do
    # shellcheck disable=SC2086
    k="$("$aqui/pj-trio" --print-kickoff $mode "$hr" 140 --repo "$hr/miembro")"
    grep -q '{{' <<<"$k" && fallo "quedan placeholders ($mode)"
    grep -q "ravn-wt clone robert-flo/miembro" <<<"$k" \
        || fallo "falta ravn-wt clone en preparación ($mode): $k"
    grep -q "ravn-wt create -r $central/repos/miembro " <<<"$k" \
        || fallo "WT_RAIZ no apunta a $central/repos/miembro ($mode): $k"
    grep -q "el bare vive en $central/.bare" <<<"$k" \
        || fallo "no documenta bare en $central/.bare ($mode)"
    if grep -v "$aqui" <<<"$k" | grep -qE '/z/bare|/z/repos'; then
        fallo "no debe referenciar /z/bare ni /z/repos ($mode)"
    fi
done

# 2. Cuando <central>/.bare/<repo>.git ya existe, NO reclona: hace fetch --prune + remote set-head.
mkdir -p "$central/.bare/miembro.git"
for mode in "" "--oneshot"; do
    # shellcheck disable=SC2086
    k="$("$aqui/pj-trio" --print-kickoff $mode "$hr" 140 --repo "$hr/miembro")"
    grep -q "git -C $central/.bare/miembro.git fetch --prune origin && git -C $central/.bare/miembro.git remote set-head origin --auto && ravn-wt create -r $central/repos/miembro " <<<"$k" \
        || fallo "con bare existente debe usar git -C ... fetch --prune origin + remote set-head ($mode): $k"
    if grep -q 'ravn-wt clone' <<<"$k"; then
        fallo "con bare existente no debe ejecutar ravn-wt clone ($mode)"
    fi
done

# 3. Proyecto normal fuera de Home Repo también usa la misma raíz central única.
pj="$tmp/pj-normal"
mkdir -p "$pj/otro"
git init -q "$pj"
git -C "$pj" remote add origin "https://github.com/robert-flo/pj-normal.git"
git init -q "$pj/otro"
git -C "$pj/otro" remote add origin "https://github.com/robert-flo/otro.git"

k_norm="$("$aqui/pj-trio" --print-kickoff "$pj" 7 --repo "$pj/otro")"
grep -q "ravn-wt clone robert-flo/otro" <<<"$k_norm" \
    || fallo "proyecto normal debe usar ravn-wt clone: $k_norm"
grep -q "ravn-wt create -r $central/repos/otro " <<<"$k_norm" \
    || fallo "proyecto normal WT_RAIZ debe ser $central/repos/otro: $k_norm"

# 4. Overrides explícitos BARE_HOME / WORKTREES_HOME se respetan.
k_ovr="$(BARE_HOME="$tmp/custom-bare" WORKTREES_HOME="$tmp/custom-wt" "$aqui/pj-trio" --print-kickoff "$hr" 140 --repo "$hr/miembro")"
grep -q "ravn-wt create -r $tmp/custom-wt/miembro " <<<"$k_ovr" \
    || fallo "override WORKTREES_HOME no respetado en WT_RAIZ: $k_ovr"
grep -q "el bare vive en $tmp/custom-bare" <<<"$k_ovr" \
    || fallo "override BARE_HOME no respetado: $k_ovr"

echo "OK centralización única bares y repos"
