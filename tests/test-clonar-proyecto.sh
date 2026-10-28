#!/usr/bin/env bash
# Proyecto meta ausente: pj-trio lo clona con try-clone (solo ése), avisa y
# sigue; en --dry-run solo muestra el comando; PJ_TRIO_NO_CLONE=1 lo apaga.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
fallo() { echo "FALLO: $*" >&2; exit 1; }

raiz="$tmp/tries"; mkdir -p "$raiz" "$tmp/bin"
export PJ_TRIO_ROOTS="$raiz"
# Stub de try: `try exec --path R clone URL` imprime un script que clona.
cat > "$tmp/bin/try" <<'STUB'
#!/usr/bin/env bash
[[ "$1 $2 $4" == "exec --path clone" ]] || { echo "try inesperado: $*" >&2; exit 2; }
echo "$*" >> "$TRY_LOG"
url="$5"; n="${url##*/}"; n="${n%.git}"; d="$3/2026-10-28-robert-flo-$n"
printf 'mkdir -p %q && git init -q %q && git -C %q remote add origin %q\n' "$d" "$d" "$d" "$url"
STUB
chmod +x "$tmp/bin/try"
# Stub de gh: existen en GitHub solo los repos listados en $GH_EXISTE.
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1 $2" == "repo view" ]] || exit 1
grep -qx "$3" <<<"${GH_EXISTE:-}"
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:/usr/bin:/bin" TRY_LOG="$tmp/try.log"

# dry-run: no clona, dice qué haría.
if out="$(cd / && "$aqui/pj-trio" --dry-run pj-nuevo 3 2>&1)"; then fallo "dry-run no debía seguir"; fi
grep -q "no está clonado: clonando robert-flo/pj-nuevo" <<<"$out" || fallo "mensaje claro: $out"
grep -q "(dry-run) se ejecutaría: try exec --path" <<<"$out" || fallo "comando en dry-run: $out"
[[ ! -e "$TRY_LOG" ]] || fallo "dry-run ejecutó try"

# Real: clona solo el meta-repo y resuelve.
k="$(cd / && "$aqui/pj-trio" --print-kickoff pj-nuevo 7 2>"$tmp/err")" || fallo "no resolvió tras clonar: $(cat "$tmp/err")"
grep -q "clonando robert-flo/pj-nuevo en $raiz con try-clone" "$tmp/err" || fallo "mensaje: $(cat "$tmp/err")"
grep -q 'gh issue view 7 -R robert-flo/pj-nuevo' <<<"$k" || fallo "kickoff: $k"
[[ "$(wc -l < "$TRY_LOG")" == 1 ]] || fallo "clonó más de una vez"
grep -q "clone https://github.com/robert-flo/pj-nuevo.git" "$TRY_LOG" || fallo "url"

# Ya clonado: no vuelve a clonar (ni con dueño/nombre).
"$aqui/pj-trio" --print-kickoff pj-nuevo 7 >/dev/null 2>&1 || fallo "segunda resolución"
"$aqui/pj-trio" --print-kickoff robert-flo/pj-nuevo 7 >/dev/null 2>&1 || fallo "dueño/nombre clonado"
[[ "$(wc -l < "$TRY_LOG")" == 1 ]] || fallo "reclonó"

# Desactivado: error de siempre.
if out="$(PJ_TRIO_NO_CLONE=1 "$aqui/pj-trio" --print-kickoff pj-otro 1 2>&1)"; then fallo "NO_CLONE"; fi
grep -q 'no se encontró el directorio del proyecto' <<<"$out" || fallo "mensaje NO_CLONE"
# Repro de Roberto: proyecto y miembro ausentes, --repo con punto final.
export GH_EXISTE="robert-flo/pj-domina-rf-git-setup"
: > "$TRY_LOG"
k="$(cd / && "$aqui/pj-trio" --print-kickoff pj-domina 3 --repo pj-domina-rf-git-setup. 2>"$tmp/err")" \
    || fallo "repro pj-domina: $(cat "$tmp/err")"
grep -q 'gh issue view 3 -R robert-flo/pj-domina-rf-git-setup' <<<"$k" || fallo "issue del miembro: $k"
grep -q "clone https://github.com/robert-flo/pj-domina.git" "$TRY_LOG" || fallo "no clonó el pj"
grep -q "clone https://github.com/robert-flo/pj-domina-rf-git-setup.git" "$TRY_LOG" || fallo "no clonó el miembro"
[[ "$(wc -l < "$TRY_LOG")" == 2 ]] || fallo "clones de más: $(cat "$TRY_LOG")"
# Miembro inexistente en GitHub: error claro, sin clon.
if out="$(cd / && "$aqui/pj-trio" --print-kickoff pj-domina 3 --repo no-existe, 2>&1)"; then fallo "aceptó inexistente"; fi
grep -q 'robert-flo/no-existe no existe en GitHub' <<<"$out" || fallo "mensaje inexistente: $out"
grep -q "no se encontró el repositorio miembro 'no-existe'" <<<"$out" || fallo "coma no recortada: $out"
[[ "$(wc -l < "$TRY_LOG")" == 2 ]] || fallo "clonó un inexistente"
echo "OK clonar proyecto"
