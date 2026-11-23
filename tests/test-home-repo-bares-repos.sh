#!/usr/bin/env bash
# Prueba de resolución de .bares/ y repos/ en un Home Repo (sin reclonar en /z/bare).
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export PJ_TRIO_OS_PROMPT="$aqui/trio-os-prompt.md"
export PATH="/usr/bin:/bin"

fallo() { echo "FALLO: $*" >&2; exit 1; }

# 1. Home Repo con .bares/ y repos/, pero SIN el bare del miembro aún:
#    resuelve BARE_HOME y WORKTREES_HOME al Home Repo y clona ahí.
hr="$tmp/HR-DEMO"
mkdir -p "$hr/.bares" "$hr/repos" "$hr/miembro"
git init -q "$hr"
git -C "$hr" remote add origin "https://github.com/robert-flo/HR-DEMO.git"
git init -q "$hr/miembro"
git -C "$hr/miembro" remote add origin "https://github.com/robert-flo/miembro.git"

for mode in "" "--oneshot"; do
    # shellcheck disable=SC2086
    k="$("$aqui/pj-trio" --print-kickoff $mode "$hr" 140 --repo "$hr/miembro")"
    grep -q '{{' <<<"$k" && fallo "quedan placeholders ($mode)"
    grep -q "BARE_HOME=$hr/.bares WORKTREES_HOME=$hr/repos ravn-git-bare-clone clone robert-flo/miembro" <<<"$k" \
        || fallo "falta BARE_HOME/WORKTREES_HOME del Home Repo en clone ($mode): $k"
    grep -q "git-create-worktree -r $hr/repos/miembro " <<<"$k" \
        || fallo "WT_RAIZ no apunta a $hr/repos/miembro ($mode): $k"
    grep -q "el bare vive en $hr/.bares" <<<"$k" \
        || fallo "no documenta bare en $hr/.bares ($mode)"
    if grep -v "$aqui" <<<"$k" | grep -qE '/z/bare|/z/repos'; then
        fallo "Home Repo no debe referenciar /z/bare ni /z/repos ($mode)"
    fi
done

# 2. Cuando <project_dir>/.bares/<repo>.git ya existe, NO reclona: hace fetch + git-create-worktree.
mkdir -p "$hr/.bares/miembro.git"
for mode in "" "--oneshot"; do
    # shellcheck disable=SC2086
    k="$("$aqui/pj-trio" --print-kickoff $mode "$hr" 140 --repo "$hr/miembro")"
    grep -q "git -C $hr/.bares/miembro.git fetch origin && git-create-worktree -r $hr/repos/miembro " <<<"$k" \
        || fallo "con bare existente debe usar git -C ... fetch origin ($mode): $k"
    if grep -q 'ravn-git-bare-clone clone' <<<"$k"; then
        fallo "con bare existente no debe ejecutar ravn-git-bare-clone clone ($mode)"
    fi
    if grep -v "$aqui" <<<"$k" | grep -qE '/z/bare|/z/repos'; then
        fallo "con bare existente no debe referenciar /z/bare ni /z/repos ($mode)"
    fi
done

# 3. Fuera de un Home Repo (sin .bares/ ni repos/), mantiene fallback /z/bare y /z/repos.
pj="$tmp/pj-normal"
mkdir -p "$pj/otro"
git init -q "$pj"
git -C "$pj" remote add origin "https://github.com/robert-flo/pj-normal.git"
git init -q "$pj/otro"
git -C "$pj/otro" remote add origin "https://github.com/robert-flo/otro.git"

k_norm="$("$aqui/pj-trio" --print-kickoff "$pj" 7 --repo "$pj/otro")"
grep -q "BARE_HOME=/z/bare WORKTREES_HOME=/z/repos ravn-git-bare-clone clone robert-flo/otro" <<<"$k_norm" \
    || fallo "fuera de Home Repo debe usar fallback /z/bare y /z/repos: $k_norm"
grep -q "git-create-worktree -r /z/repos/otro " <<<"$k_norm" \
    || fallo "fuera de Home Repo WT_RAIZ debe ser /z/repos/otro: $k_norm"

# 4. Overrides explícitos BARE_HOME / WORKTREES_HOME se respetan también en Home Repo.
k_ovr="$(BARE_HOME="$tmp/custom-bare" WORKTREES_HOME="$tmp/custom-wt" "$aqui/pj-trio" --print-kickoff "$hr" 140 --repo "$hr/miembro")"
grep -q "BARE_HOME=$tmp/custom-bare WORKTREES_HOME=$tmp/custom-wt ravn-git-bare-clone clone robert-flo/miembro" <<<"$k_ovr" \
    || fallo "override explícito no respetado: $k_ovr"
grep -q "git-create-worktree -r $tmp/custom-wt/miembro " <<<"$k_ovr" \
    || fallo "override WORKTREES_HOME no respetado en WT_RAIZ: $k_ovr"

echo "OK home-repo bares y repos"
