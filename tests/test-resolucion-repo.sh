#!/usr/bin/env bash
# Resolución de proyecto y miembro sin depender de $PWD: clones de try
# (AAAA-MM-DD-dueño-nombre), de try-clone (rf-nombre dentro del pj) y nombre
# corto (--repo rf-git-setup → pj-domina-rf-git-setup). El issue se lee en el
# miembro (gh -R dueño/miembro), no en el meta-repo.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PATH="/usr/bin:/bin"
fallo() { echo "FALLO: $*" >&2; exit 1; }

raiz="$tmp/tries"
clon() { mkdir -p "$1" && git init -q "$1" && git -C "$1" remote add origin "https://github.com/robert-flo/$2.git"; }
clon "$raiz/2026-10-26-robert-flo-pj-ravn" pj-ravn
printf 'proyecto: "pj-ravn"\nrepos:\n  - dir: "x"\n    repo: "robert-flo/pj-domina-rf-git-setup"\n' > "$raiz/2026-10-26-robert-flo-pj-ravn/proyecto.yml"
clon "$raiz/2026-10-26-robert-flo-pj-ravn/rf-pj-domina-rf-git-setup" pj-domina-rf-git-setup
clon "$raiz/2026-10-26-robert-flo-pj-ravn/rf-pj-domina-rf-git-setup-arch" pj-domina-rf-git-setup-arch
clon "$raiz/2026-10-27-robert-flo-otro" otro-rf-tools
clon "$raiz/2026-10-27-robert-flo-otro2" otro2-rf-tools
export PJ_TRIO_ROOTS="$raiz"

for cwd in / "$tmp" "$raiz" "$raiz/2026-10-26-robert-flo-pj-ravn"; do
    for t in 1 4; do
        k="$(cd "$cwd" && "$aqui/pj-trio" --print-kickoff pj-ravn "$t" --repo rf-git-setup 2>&1)" \
            || fallo "nombre corto falló (cwd=$cwd ticket=$t): $k"
        grep -q "gh issue view $t -R robert-flo/pj-domina-rf-git-setup --comments" <<<"$k" \
            || fallo "el issue se lee en el miembro (cwd=$cwd ticket=$t)"
        grep -q "repo de trabajo: $raiz/2026-10-26-robert-flo-pj-ravn/rf-pj-domina-rf-git-setup)" <<<"$k" \
            || fallo "miembro equivocado (cwd=$cwd ticket=$t)"
    done
done

out="$(cd / && "$aqui/pj-trio" --dry-run pj-ravn 4 --repo pj-domina-rf-git-setup-arch 2>&1)"
grep -q 'Workspace label: trio pj-ravn/pj-domina-rf-git-setup-arch#4' <<<"$out" || fallo "label con nombres canónicos: $out"
grep -q 'herdr agent start "pm-pj-ravn-pj-domina-rf-git-setup-arch-4"' <<<"$out" || fallo "agente por miembro y ticket"
out="$(cd / && "$aqui/pj-trio" --dry-run pj-ravn 4 --repo robert-flo/pj-domina-rf-git-setup 2>&1)"
grep -q 'Workspace label: trio pj-ravn/pj-domina-rf-git-setup#4' <<<"$out" || fallo "dueño/nombre"

# Sin --repo el issue es del meta-repo.
k="$(cd / && "$aqui/pj-trio" --print-kickoff pj-ravn 9)"
grep -q 'gh issue view 9 -R robert-flo/pj-ravn' <<<"$k" || fallo "issue del meta-repo"

# Ambiguo y ausente: error claro.
if out="$(cd / && "$aqui/pj-trio" --print-kickoff pj-ravn 1 --repo rf-tools 2>&1)"; then fallo "aceptó ambiguo"; fi
grep -q 'ambiguo' <<<"$out" || fallo "mensaje de ambiguo"
if out="$(cd / && "$aqui/pj-trio" --print-kickoff pj-ravn 1 --repo no-existe 2>&1)"; then fallo "aceptó ausente"; fi
grep -q 'no se encontró el repositorio miembro' <<<"$out" || fallo "mensaje de ausente"
echo "OK resolución"
