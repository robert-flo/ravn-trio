#!/usr/bin/env bash
# Pruebas de --kind <agy|cursor> en pj-trio (start, --oneshot, --dry-run, --print-kickoff).
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/HR-DEMO"
git init -q "$tmp/miembro"
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export TRIO_SHARE_DIR="$tmp/noexiste"
export PATH="/usr/bin:/bin"

fallo() { echo "FALLO: $*" >&2; exit 1; }

# 1. --dry-run --kind cursor (trío con --repo)
out="$("$aqui/pj-trio" --dry-run --kind cursor "$tmp/HR-DEMO" 89 --repo "$tmp/miembro" 2>&1)"
grep -q "Kinds: PM='cursor' WK='cursor' RV='cursor'" <<<"$out" || fallo "no reportó Kinds cursor: $out"

pm_line="$(grep 'herdr agent start "pm-miembro-89"' <<<"$out" || true)"
[[ -n "$pm_line" ]] || fallo "falta herdr agent start para pm-miembro-89"
grep -q -- '--kind "cursor"' <<<"$pm_line" || fallo "PM sin --kind cursor: $pm_line"
grep -q -- '--yolo --trust --workspace "'"$tmp"'/miembro" --add-dir "'"$tmp"'/HR-DEMO"' <<<"$pm_line" \
    || fallo "PM sin flags esperados: $pm_line"
grep -q "@$tmp/HR-DEMO/.cursor/rules/pm-trio-hr-demo.mdc Lee y segui al pie de la letra las instrucciones de arranque del archivo $tmp/HR-DEMO/.trio/miembro-89/kickoff.md" <<<"$pm_line" \
    || fallo "PM sin mención absoluta a pm-trio-hr-demo.mdc + kickoff: $pm_line"

for rol in wk rv; do
    rline="$(grep "herdr agent start \"${rol}-miembro-89\"" <<<"$out" || true)"
    [[ -n "$rline" ]] || fallo "falta herdr agent start para ${rol}-miembro-89"
    grep -q -- '--kind "cursor"' <<<"$rline" || fallo "$rol sin --kind cursor: $rline"
    grep -q -- '--yolo --trust --workspace "'"$tmp"'/miembro" --add-dir "'"$tmp"'/HR-DEMO"' <<<"$rline" \
        || fallo "$rol sin flags esperados: $rline"
    if grep -q '.cursor/rules/' <<<"$rline"; then
        fallo "$rol no debe llevar prompt posicional al arranque: $rline"
    fi
done

if grep -q 'herdr agent prompt' <<<"$out"; then
    fallo "PM recibió kickoff inline; no debe llamar herdr agent prompt"
fi

# 2. --dry-run --oneshot --kind cursor
out_os="$("$aqui/pj-trio" --dry-run --oneshot --kind cursor "$tmp/HR-DEMO" 89 --repo "$tmp/miembro" 2>&1)"
grep -q "Kinds: OS='cursor'" <<<"$out_os" || fallo "oneshot no reportó Kinds: OS='cursor'"
os_line="$(grep 'herdr agent start "os-miembro-89"' <<<"$out_os" || true)"
[[ -n "$os_line" ]] || fallo "falta herdr agent start para os-miembro-89"
grep -q -- '--kind "cursor"' <<<"$os_line" || fallo "OS sin --kind cursor: $os_line"
grep -q -- '--yolo --trust --workspace "'"$tmp"'/miembro" --add-dir "'"$tmp"'/HR-DEMO"' <<<"$os_line" \
    || fallo "OS sin flags esperados: $os_line"
grep -q "@$tmp/HR-DEMO/.cursor/rules/os-hr-demo.mdc Lee y segui al pie de la letra las instrucciones de arranque del archivo $tmp/HR-DEMO/.trio/miembro-89/kickoff.md" <<<"$os_line" \
    || fallo "OS sin mención absoluta a os-hr-demo.mdc + kickoff: $os_line"

# 3. --kind agy explícito y default sin --kind (contrato agy intacto, incluso con PJ_TRIO_KIND=cursor)
out_agy="$("$aqui/pj-trio" --dry-run --kind agy "$tmp/HR-DEMO" 89 --repo "$tmp/miembro" 2>&1)"
out_def="$(PJ_TRIO_KIND=cursor "$aqui/pj-trio" --dry-run "$tmp/HR-DEMO" 89 --repo "$tmp/miembro" 2>&1)"
for o in "$out_agy" "$out_def"; do
    grep -q "Kinds: PM='agy' WK='agy' RV='agy'" <<<"$o" || fallo "regresión en Kinds agy"
    grep -q -- '--agent "PM-HR-DEMO"' <<<"$o" || fallo "regresión en --agent PM-HR-DEMO"
    if grep -qE -- 'herdr agent start .*(--yolo|--trust|--workspace)' <<<"$o"; then
        fallo "agy no debe imprimir flags de cursor"
    fi
done

# 4. --print-kickoff --kind cursor vs agy
k_cur="$("$aqui/pj-trio" --print-kickoff --kind cursor "$tmp/HR-DEMO" 89 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k_cur" && fallo "quedan placeholders en kickoff cursor"
grep -qF "herdr agent prompt wk-miembro-89 \"@$tmp/HR-DEMO/.cursor/rules/wk-hr-demo.mdc Sos WK del ticket #89." <<<"$k_cur" \
    || fallo "kickoff cursor sin prefijo de regla para WK"
grep -qF "herdr agent prompt rv-miembro-89 \"@$tmp/HR-DEMO/.cursor/rules/rv-hr-demo.mdc Sos RV del ticket #89." <<<"$k_cur" \
    || fallo "kickoff cursor sin prefijo de regla para RV"
grep -q -- '--timeout 600000' <<<"$k_cur" || fallo "kickoff cursor sin --timeout 600000"
grep -q 'wk.md' <<<"$k_cur" || fallo "kickoff cursor sin verificación de wk.md"
grep -q 'rv.md' <<<"$k_cur" || fallo "kickoff cursor sin verificación de rv.md"

k_agy="$("$aqui/pj-trio" --print-kickoff --kind agy "$tmp/HR-DEMO" 89 --repo "$tmp/miembro")"
if grep -q '.cursor/rules/' <<<"$k_agy"; then
    fallo "kickoff agy no debe incluir rutas de .cursor/rules"
fi

# 5. --kind inválido falla rápido
if "$aqui/pj-trio" --dry-run --kind invalido "$tmp/HR-DEMO" 89 2>/dev/null; then
    fallo "aceptó --kind invalido"
fi

# 6. Sin --dry-run, falla rápido si falta cursor-agent (ni PATH ni mise) antes de tocar herdr
mkdir -p "$tmp/bin_no_cursor"
cat > "$tmp/bin_no_cursor/herdr" <<'EOF'
#!/bin/sh
echo "herdr_called" >&2
exit 99
EOF
cat > "$tmp/bin_no_cursor/mise" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/bin_no_cursor/herdr" "$tmp/bin_no_cursor/mise"
err_missing="$(PATH="$tmp/bin_no_cursor:/usr/bin:/bin" "$aqui/pj-trio" --kind cursor "$tmp/HR-DEMO" 89 2>&1 || true)"
grep -q 'cursor-agent' <<<"$err_missing" || fallo "no reportó falta de cursor-agent: $err_missing"
if grep -q 'herdr_called' <<<"$err_missing"; then
    fallo "llamó a herdr antes de validar cursor-agent"
fi

# 7. Validación vía mise x cursor-agent pasa y avanza hasta herdr
mkdir -p "$tmp/bin_mise"
cp "$tmp/bin_no_cursor/herdr" "$tmp/bin_mise/herdr"
cat > "$tmp/bin_mise/mise" <<'EOF'
#!/bin/sh
if [ "$1" = "x" ] && [ "$2" = "cursor-agent" ]; then
    exit 0
fi
exit 1
EOF
chmod +x "$tmp/bin_mise/mise"
err_mise="$(PATH="$tmp/bin_mise:/usr/bin:/bin" "$aqui/pj-trio" --kind cursor "$tmp/HR-DEMO" 89 2>&1 || true)"
grep -q 'herdr_called' <<<"$err_mise" || fallo "con mise x cursor-agent válido no avanzó a herdr: $err_mise"

echo "OK kind cursor"
