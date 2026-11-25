#!/usr/bin/env bash
# Pruebas de `pj-trio watch`: modo accionable por defecto, --verbose para pasos, blocked, salida legible, timeout y alias w.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }
now_iso="$(date --iso-8601=seconds)"

pj="$tmp/HR-DEMO"
git init -q "$pj"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
EOF

mkdir -p "$pj/.trio/ravn-trio-21"
cat > "$pj/.trio/ravn-trio-21/status.json" <<EOF
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF

mkdir -p "$tmp/bin_stubs"
cat > "$tmp/bin_stubs/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin_stubs/notify-send"
state_file="$tmp/herdr_mode"
echo "running" > "$state_file"

cat > "$tmp/bin_stubs/herdr" <<EOF
#!/usr/bin/env bash
mode="\$(cat "$state_file" 2>/dev/null || echo running)"
case "\${1:-} \${2:-}" in
  "agent get")
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"\${3:-}\",\"agent_status\":\"\$mode\"}}}"
    ;;
  "agent read")
    for i in \$(seq 1 30); do
      echo "linea-\$i de \${3:-}"
    done
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/herdr"

inotify_mode="$tmp/inotify_mode"
inotify_step="$tmp/inotify_step"
echo "noop" > "$inotify_mode"
echo "0" > "$inotify_step"

cat > "$tmp/bin_stubs/inotifywait" <<EOF
#!/usr/bin/env bash
mode="\$(cat "$inotify_mode" 2>/dev/null || echo noop)"
case "\$mode" in
  absorb_pasos_then_hecho)
    step="\$(cat "$inotify_step" 2>/dev/null || echo 0)"
    step=\$(( step + 1 ))
    echo "\$step" > "$inotify_step"
    if [[ "\$step" -eq 1 ]]; then
      cat > "$pj/.trio/ravn-trio-21/status.json" <<JSON
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "rv",
  "timestamp": "$now_iso"
}
JSON
      exit 0
    fi
    cat > "$pj/.trio/ravn-trio-21/status.json" <<JSON
{
  "ticket": "ravn-trio-21",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "$now_iso"
}
JSON
    exit 0
    ;;
  change_paso)
    cat > "$pj/.trio/ravn-trio-21/status.json" <<JSON
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "rv",
  "timestamp": "$now_iso"
}
JSON
    exit 0
    ;;
  change_needs_roberto)
    cat > "$pj/.trio/ravn-trio-21/status.json" <<'JSON'
{
  "ticket": "ravn-trio-21",
  "estado": "needs-roberto",
  "paso": "merge",
  "timestamp": "2026-11-17T09:10:00-06:00"
}
JSON
    exit 0
    ;;
  sleep_timeout)
    sleep 2
    exit 2
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/inotifywait"

# 1. Modo --verbose: diff inmediato contra --snapshot por cambio de paso
snap="$tmp/snap.json"
cat > "$snap" <<EOF
{
  "ravn-trio-21": {
    "clave": "ravn-trio-21",
    "ticket": "ravn-trio-21",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "plan",
    "pm_agent": "pm-ravn-trio-21",
    "pm_herdr_status": "running",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF

out_snap="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --verbose --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].tipo == "paso" and .events[0].paso == "wk"' <<<"$out_snap" >/dev/null \
  || fallo "diff con --verbose contra --snapshot inesperado: $out_snap"
jq -e '.["ravn-trio-21"].paso == "wk"' "$snap" >/dev/null \
  || fallo "snapshot no se actualizó tras diff --verbose"

# 2. Modo --verbose: detección de cambio de paso vía inotifywait y alias w
echo "change_paso" > "$inotify_mode"
out_paso="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" w "$pj" --snapshot "$snap" --timeout 10 --verbose --json)"
jq -e '.status == "changed" and .events[0].tipo == "paso" and .events[0].prev_paso == "wk" and .events[0].paso == "rv"' <<<"$out_paso" >/dev/null \
  || fallo "detección de cambio de paso con --verbose falló: $out_paso"

# 3. Modo por defecto: absorbe plan -> wk -> rv (actualizando snapshot) y despierta en hecho
cat > "$pj/.trio/ravn-trio-21/status.json" <<EOF
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
cat > "$snap" <<EOF
{
  "ravn-trio-21": {
    "clave": "ravn-trio-21",
    "ticket": "ravn-trio-21",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "plan",
    "pm_agent": "pm-ravn-trio-21",
    "pm_herdr_status": "running",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
echo "absorb_pasos_then_hecho" > "$inotify_mode"
echo "0" > "$inotify_step"
out_hecho="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].tipo == "estado" and .events[0].estado == "hecho" and .events[0].prev_estado == "en-curso"' <<<"$out_hecho" >/dev/null \
  || fallo "modo por defecto debía absorber pasos y despertar en hecho: $out_hecho"
jq -e '.["ravn-trio-21"].estado == "hecho" and .["ravn-trio-21"].paso == "merge"' "$snap" >/dev/null \
  || fallo "snapshot no se actualizó tras hecho"

# 3b. Modo por defecto: ticket nuevo en en-curso no despierta; ticket nuevo en hecho sí despierta
mkdir -p "$pj/.trio/ravn-trio-22"
cat > "$pj/.trio/ravn-trio-22/status.json" <<EOF
{
  "ticket": "ravn-trio-22",
  "estado": "en-curso",
  "paso": "plan",
  "timestamp": "$now_iso"
}
EOF
echo "change_needs_roberto" > "$inotify_mode"
out_nr="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "ravn-trio-21" and .events[0].tipo == "estado" and .events[0].estado == "needs-roberto"' <<<"$out_nr" >/dev/null \
  || fallo "detección de needs-roberto (ignorando nuevo en-curso) falló: $out_nr"
tail_lines="$(jq -r '.events[0].tail' <<<"$out_nr" | wc -l)"
[[ "$tail_lines" -eq 25 ]] || fallo "esperaba 25 líneas en tail, obtuve $tail_lines"
jq -r '.events[0].tail' <<<"$out_nr" | grep -q 'linea-30 de pm-ravn-trio-21' \
  || fallo "tail no contiene la última línea esperada"

mkdir -p "$pj/.trio/ravn-trio-23"
cat > "$pj/.trio/ravn-trio-23/status.json" <<'EOF'
{
  "ticket": "ravn-trio-23",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:12:00-06:00"
}
EOF
out_nuevo_hecho="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "ravn-trio-23" and .events[0].tipo == "nuevo" and .events[0].estado == "hecho"' <<<"$out_nuevo_hecho" >/dev/null \
  || fallo "ticket nuevo ya en hecho debía despertar: $out_nuevo_hecho"

rm -rf "$pj/.trio/ravn-trio-22" "$pj/.trio/ravn-trio-23"

# 4. Detección de blocked en herdr agent get dentro del loop sin cambios en status.json
cat > "$pj/.trio/ravn-trio-21/status.json" <<EOF
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
echo "noop" > "$inotify_mode"
rm -f "$snap"
calls_file="$tmp/herdr_calls"
: > "$calls_file"
cat > "$tmp/bin_stubs/herdr" <<EOF
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in
  "agent get")
    echo "get" >> "$calls_file"
    n=\$(wc -l < "$calls_file")
    if [[ "\$n" -le 1 ]]; then
      status="running"
    else
      status="blocked"
    fi
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"\${3:-}\",\"agent_status\":\"\$status\"}}}"
    ;;
  "agent read")
    for i in \$(seq 1 30); do
      echo "linea-\$i de \${3:-}"
    done
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/herdr"

out_blk="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and .events[0].tipo == "pm_herdr_status" and .events[0].pm_herdr_status == "blocked"' <<<"$out_blk" >/dev/null \
  || fallo "detección de blocked en loop falló: $out_blk"
jq -r '.events[0].tail' <<<"$out_blk" | grep -q 'linea-30 de pm-ravn-trio-21' \
  || fallo "blocked debía capturar últimas 25 líneas de herdr agent read"

# 4b. Salida legible (sin --json) muestra resumen y últimas líneas
cat > "$snap" <<EOF
{
  "ravn-trio-21": {
    "clave": "ravn-trio-21",
    "ticket": "ravn-trio-21",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-21",
    "pm_herdr_status": "running",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
out_human="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10)"
grep -q 'Watch — HR-DEMO' <<<"$out_human" || fallo "falta encabezado Watch en salida legible: $out_human"
grep -q 'ravn-trio-21 \[pm_herdr_status\]' <<<"$out_human" || fallo "falta evento en salida legible: $out_human"
grep -q 'linea-30 de pm-ravn-trio-21' <<<"$out_human" || fallo "falta tail en salida legible: $out_human"

# 5. Timeout sale con 124
cat > "$tmp/bin_stubs/herdr" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "agent get")
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"${3:-}\",\"agent_status\":\"running\"}}}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/herdr"
echo "sleep_timeout" > "$inotify_mode"
rc=0
out_to="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 1 --json)" || rc=$?
[[ "$rc" -eq 124 ]] || fallo "esperaba exit 124 en timeout, obtuve $rc ($out_to)"
jq -e '.status == "timeout"' <<<"$out_to" >/dev/null \
  || fallo "salida JSON de timeout inesperada: $out_to"

# 6. --ticket: validación de argumentos vacíos o faltantes -> exit 1
check_bad_ticket() {
  local rc=0 err=""
  err="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" "$@" 2>&1)" || rc=$?
  [[ "$rc" -eq 1 ]] || fallo "esperaba exit 1 para ($*), obtuve $rc ($err)"
  [[ "$err" != *"opción desconocida"* ]] || fallo "--ticket debería ser reconocida, no desconocida ($err)"
}
check_bad_ticket --ticket
check_bad_ticket --ticket ""
check_bad_ticket --ticket ","
check_bad_ticket --ticket "a,,b"
check_bad_ticket --ticket "a,"
check_bad_ticket --ticket --json

# 7. --ticket: ignora cambios en otros tickets (124), no llama herdr agent get en ajenos, y despierta con el filtrado (JSON y texto)
mkdir -p "$pj/.trio/rf-dotfiles-55"
cat > "$pj/.trio/ravn-trio-21/status.json" <<EOF
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF

herdr_log="$tmp/herdr_ticket_log"
: > "$herdr_log"
cat > "$tmp/bin_stubs/herdr" <<EOF
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in
  "agent get")
    echo "\${3:-}" >> "$herdr_log"
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"\${3:-}\",\"agent_status\":\"running\"}}}"
    ;;
  "agent read")
    echo "linea-tail de \${3:-}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/herdr"

cat > "$tmp/bin_stubs/inotifywait" <<EOF
#!/usr/bin/env bash
mode="\$(cat "$inotify_mode" 2>/dev/null || echo noop)"
case "\$mode" in
  change_other_then_sleep)
    cat > "$pj/.trio/ravn-trio-21/status.json" <<'JSON'
{
  "ticket": "ravn-trio-21",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:21:00-06:00"
}
JSON
    sleep 2
    exit 0
    ;;
  change_filtered_55)
    cat > "$pj/.trio/rf-dotfiles-55/status.json" <<'JSON'
{
  "ticket": "rf-dotfiles-55",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:22:00-06:00"
}
JSON
    exit 0
    ;;
  sleep_timeout)
    sleep 2
    exit 2
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/inotifywait"

echo "change_other_then_sleep" > "$inotify_mode"
rc=0
out_other="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket rf-dotfiles-55 --timeout 1 --json)" || rc=$?
[[ "$rc" -eq 124 ]] || fallo "esperaba exit 124 al cambiar otro ticket, obtuve $rc ($out_other)"
if grep -q 'ravn-trio-21' "$herdr_log"; then
  fallo "no debía invocar herdr agent get para ticket ajeno ravn-trio-21: $(cat "$herdr_log")"
fi

echo "change_filtered_55" > "$inotify_mode"
out_f55="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket rf-dotfiles-55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55" and .events[0].estado == "hecho"' <<<"$out_f55" >/dev/null \
  || fallo "esperaba evento de rf-dotfiles-55 en --json: $out_f55"

# Mismo caso en salida de texto legible
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
out_f55_txt="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket rf-dotfiles-55 --timeout 5)"
grep -q 'rf-dotfiles-55 \[estado\]' <<<"$out_f55_txt" \
  || fallo "esperaba evento de rf-dotfiles-55 en salida legible: $out_f55_txt"
if grep -q 'ravn-trio-21' <<<"$out_f55_txt"; then
  fallo "no debía aparecer ticket ajeno en salida legible: $out_f55_txt"
fi

# 8. --ticket: repetido, separado por comas, sufijo numérico y campo .ticket del JSON
mkdir -p "$pj/.trio/custom-dir"
cat > "$pj/.trio/custom-dir/status.json" <<EOF
{
  "ticket": "alias-99",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
echo "change_filtered_55" > "$inotify_mode"
# Match numérico: --ticket 55 matchea rf-dotfiles-55
out_num="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket 55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55"' <<<"$out_num" >/dev/null \
  || fallo "match numérico --ticket 55 falló: $out_num"

# Repetido: --ticket ravn-trio-21 --ticket 55
# ravn-trio-21 quedó en hecho en el caso 7; si no se reinicia, el arranque
# con --ticket lo toma como evento y no llega a ver el cambio de 55.
cat > "$pj/.trio/ravn-trio-21/status.json" <<EOF
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
out_rep="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket ravn-trio-21 --ticket 55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55"' <<<"$out_rep" >/dev/null \
  || fallo "--ticket repetido falló: $out_rep"

# Separado por comas: --ticket alias-99,rf-dotfiles-55
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
out_csv="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket alias-99,rf-dotfiles-55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55"' <<<"$out_csv" >/dev/null \
  || fallo "--ticket separado por comas falló: $out_csv"

# 9. Race condition en arranque sin --snapshot:
# 9a. Con --ticket y ticket ya en hecho -> despierta inmediato (exit 0)
echo "sleep_timeout" > "$inotify_mode"
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<'EOF'
{
  "ticket": "rf-dotfiles-55",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:25:00-06:00"
}
EOF
out_race_hecho="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket rf-dotfiles-55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55" and .events[0].estado == "hecho"' <<<"$out_race_hecho" >/dev/null \
  || fallo "race condition con --ticket ya en hecho falló: $out_race_hecho"

# 9b. Con --ticket (matching por campo .ticket) y ya en needs-roberto -> despierta inmediato (exit 0)
cat > "$pj/.trio/custom-dir/status.json" <<'EOF'
{
  "ticket": "alias-99",
  "estado": "needs-roberto",
  "paso": "merge",
  "timestamp": "2026-11-17T09:26:00-06:00"
}
EOF
out_race_nr="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket alias-99 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "custom-dir" and .events[0].estado == "needs-roberto"' <<<"$out_race_nr" >/dev/null \
  || fallo "race condition con --ticket ya en needs-roberto (match .ticket) falló: $out_race_nr"
jq -r '.events[0].tail' <<<"$out_race_nr" | grep -q 'linea-tail de' \
  || fallo "race condition needs-roberto debía incluir tail: $out_race_nr"

# 9c. Con --ticket y ya en en-curso con pm_herdr_status blocked -> despierta inmediato (exit 0)
cat > "$pj/.trio/rf-dotfiles-55/status.json" <<EOF
{
  "ticket": "rf-dotfiles-55",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "$now_iso"
}
EOF
cat > "$tmp/bin_stubs/herdr" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "agent get")
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"${3:-}\",\"agent_status\":\"blocked\"}}}"
    ;;
  "agent read")
    echo "linea-blocked de ${3:-}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_stubs/herdr"
out_race_blk="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --ticket 55 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "rf-dotfiles-55" and .events[0].pm_herdr_status == "blocked"' <<<"$out_race_blk" >/dev/null \
  || fallo "race condition con --ticket ya en blocked falló: $out_race_blk"

# 9d. Sin --ticket y sin --snapshot: un ticket ya en hecho NO despierta -> timeout 124
rm -rf "$pj/.trio/custom-dir" "$pj/.trio/rf-dotfiles-55"
cat > "$pj/.trio/ravn-trio-21/status.json" <<'EOF'
{
  "ticket": "ravn-trio-21",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:28:00-06:00"
}
EOF
rc=0
out_no_filter="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --timeout 1 --json)" || rc=$?
[[ "$rc" -eq 124 ]] || fallo "sin --ticket un ticket ya en hecho NO debía despertar, obtuve rc=$rc ($out_no_filter)"

# 10. Ayuda y completion incluyen --ticket
"$aqui/pj-trio" watch --help | grep -q -- '--ticket' \
  || fallo "pj-trio watch --help debe documentar --ticket"
comp_out="$(bash -c '
  source "'"$aqui"'/runtime/completion/pj-trio.bash"
  COMP_WORDS=(pj-trio watch --)
  COMP_CWORD=2
  _pj_trio_completion
  printf "%s\n" "${COMPREPLY[@]}"
')"
grep -qx -- '--ticket' <<<"$comp_out" \
  || fallo "completion de pj-trio watch debe incluir --ticket, obtuve: $comp_out"

# 11. Sin <proyecto>: mismo Home Repo que la ruta, y --ticket sigue filtrando.
mkdir -p "$pj/sub"
cat > "$pj/.trio/ravn-trio-21/status.json" <<'EOF'
{
  "ticket": "ravn-trio-21",
  "estado": "hecho",
  "paso": "merge",
  "timestamp": "2026-11-17T09:30:00-06:00"
}
EOF
out_cwd="$(cd "$pj/sub" && PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch --ticket ravn-trio-21 --timeout 5 --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].clave == "ravn-trio-21"' <<<"$out_cwd" >/dev/null \
  || fallo "watch sin <proyecto> y con --ticket no infirió el Home Repo: $out_cwd"
rc=0
err="$(cd "$tmp" && PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch --timeout 1 --json 2>&1)" || rc=$?
[[ "$rc" -ne 0 ]] || fallo "watch fuera de un Home Repo debía fallar"
grep -q '<proyecto>' <<<"$err" || fallo "watch fuera de un Home Repo debía pedir <proyecto>: $err"
"$aqui/pj-trio" watch --help | grep -q 'Si se omite' \
  || fallo "pj-trio watch --help debe decir que <proyecto> se puede omitir"

# 12. estado_real (sin-cuota, colgado, muerto, terminado), .session en herdr y gh selectivo.
pj_sess="$tmp/HR-SESS"
git init -q "$pj_sess"
git -C "$pj_sess" remote add origin "https://github.com/o/HR-SESS.git"
cat > "$pj_sess/proyecto.yml" <<'EOF'
proyecto: HR-SESS
EOF
mkdir -p "$pj_sess/.trio/ravn-trio-31" "$pj_sess/.trio/ravn-trio-32"

cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<EOF
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
EOF
cat > "$pj_sess/.trio/ravn-trio-32/status.json" <<EOF
{
  "ticket": "ravn-trio-32",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-32",
  "session": "spec-231",
  "pr": "https://github.com/o/ravn-trio/pull/32",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
EOF

sess_herdr_mode="$tmp/sess_herdr_mode"
echo "quota" > "$sess_herdr_mode"
mkdir -p "$tmp/bin_sess"
cat > "$tmp/bin_sess/herdr" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" != "--session" || "\${2:-}" != "spec-231" ]]; then
  exit 1
fi
shift 2
mode="\$(cat "$sess_herdr_mode" 2>/dev/null || echo quota)"
case "\${1:-} \${2:-}" in
  "workspace list")
    echo '{"result":{"workspaces":[{"workspace_id":"ws31","label":"trio HR-SESS/ravn-trio#31"},{"workspace_id":"ws32","label":"trio HR-SESS/ravn-trio#32"}]}}'
    ;;
  "agent list")
    echo '{"result":{"agents":[{"name":"pm-ravn-trio-31","agent_status":"idle","workspace_id":"ws31"},{"name":"wk-ravn-trio-31","agent_status":"running","workspace_id":"ws31"},{"name":"pm-ravn-trio-32","agent_status":"idle","workspace_id":"ws32"},{"name":"wk-ravn-trio-32","agent_status":"running","workspace_id":"ws32"}]}}'
    ;;
  "agent get")
    case "\${3:-}" in
      wk-ravn-trio-31)
        if [[ "\$mode" == "dead" ]]; then
          echo '{"result":{"agent":{"name":"wk-ravn-trio-31","agent_status":"exited","workspace_id":"ws31"}}}'
        else
          echo '{"result":{"agent":{"name":"wk-ravn-trio-31","agent_status":"running","workspace_id":"ws31"}}}'
        fi
        ;;
      wk-ravn-trio-32)
        if [[ "\$mode" == "dead32" ]]; then
          echo '{"result":{"agent":{"name":"wk-ravn-trio-32","agent_status":"exited","workspace_id":"ws32"}}}'
        else
          echo '{"result":{"agent":{"name":"wk-ravn-trio-32","agent_status":"running","workspace_id":"ws32"}}}'
        fi
        ;;
      pm-ravn-trio-*)
        echo '{"result":{"agent":{"name":"'"\${3:-}"'","agent_status":"idle","workspace_id":"ws31"}}}'
        ;;
      *) exit 1 ;;
    esac
    ;;
  "agent read")
    if [[ "\$mode" == "quota" && "\${3:-}" == "wk-ravn-trio-31" ]]; then
      echo "Error 429: rate limit exceeded"
    else
      echo "working normally"
    fi
    ;;
  *) exit 1 ;;
esac
EOF
cp "$tmp/bin_stubs/inotifywait" "$tmp/bin_sess/inotifywait"
cp "$tmp/bin_stubs/notify-send" "$tmp/bin_sess/notify-send"
chmod +x "$tmp/bin_sess/herdr" "$tmp/bin_sess/inotifywait" "$tmp/bin_sess/notify-send"

gh_watch_log="$tmp/gh_watch.log"
: > "$gh_watch_log"
cat > "$tmp/bin_sess/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$gh_watch_log"
case "\${1:-} \${2:-}" in
  "pr view") echo '{"state":"MERGED","reviewDecision":"APPROVED","statusCheckRollup":[]}' ;;
  "issue view") echo '{"state":"CLOSED"}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin_sess/gh"

# 12a. Respeta .session y detecta vivo -> sin-cuota en --json y legible
snap_sess="$tmp/snap_sess.json"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
out_quota="$(PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess" --json)"
jq -e '.status == "changed" and .events[0].tipo == "estado_real" and .events[0].estado_real == "sin-cuota" and .events[0].prev_estado_real == "vivo"' <<<"$out_quota" >/dev/null \
  || fallo "transición vivo -> sin-cuota con .session falló: $out_quota"

# Salida legible de estado_real
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
out_quota_txt="$(PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess")"
grep -q 'real=sin-cuota' <<<"$out_quota_txt" || fallo "falta real=sin-cuota en salida legible: $out_quota_txt"
grep -q 'estado_real: vivo -> sin-cuota' <<<"$out_quota_txt" || fallo "falta transición estado_real en salida legible: $out_quota_txt"

# 12b. Transición vivo -> colgado
echo "ok" > "$sess_herdr_mode"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<'EOF'
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "2020-01-01T00:00:00-06:00",
  "timestamp": "2020-01-01T00:00:00-06:00"
}
EOF
out_colgado="$(PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess" --json)"
jq -e '.status == "changed" and .events[0].tipo == "estado_real" and .events[0].estado_real == "colgado" and .events[0].prev_estado_real == "vivo"' <<<"$out_colgado" >/dev/null \
  || fallo "transición vivo -> colgado falló: $out_colgado"

# 12c. Transición vivo -> muerto (sin gh)
echo "dead" > "$sess_herdr_mode"
cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<EOF
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
EOF
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
out_muerto="$(PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess" --json)"
jq -e '.status == "changed" and .events[0].tipo == "estado_real" and .events[0].estado_real == "muerto" and .events[0].prev_estado_real == "vivo"' <<<"$out_muerto" >/dev/null \
  || fallo "transición vivo -> muerto falló: $out_muerto"

# 12d. Tick normal no llama gh; muerto con PR MERGED + issue CLOSED confirma terminado vía gh
: > "$gh_watch_log"
echo "ok" > "$sess_herdr_mode"
echo "sleep_timeout" > "$inotify_mode"
rc=0
PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-32 --timeout 1 --json >/dev/null || rc=$?
[[ "$rc" -eq 124 ]] || fallo "esperaba timeout 124 en tick normal vivo, obtuve $rc"
if [[ -s "$gh_watch_log" ]]; then
  fallo "tick rápido sin transición no debía consultar gh: $(cat "$gh_watch_log")"
fi

echo "dead32" > "$sess_herdr_mode"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-32": {
    "clave": "ravn-trio-32",
    "ticket": "ravn-trio-32",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-32",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "https://github.com/o/ravn-trio/pull/32",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
out_term="$(PATH="$tmp/bin_sess:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-32 --snapshot "$snap_sess" --json)"
jq -e '.status == "changed" and .events[0].tipo == "estado_real" and .events[0].estado_real == "terminado" and .events[0].prev_estado_real == "vivo"' <<<"$out_term" >/dev/null \
  || fallo "confirmación de terminado vía gh falló: $out_term"
[[ -s "$gh_watch_log" ]] || fallo "se esperaba consulta selectiva a gh para confirmar terminado"

# 13. Notificaciones (herdr notification show + fallback notify-send), --no-notify y --loop.
herdr_notif_log="$tmp/herdr_notif.log"
notify_send_log="$tmp/notify_send.log"
notif_fail_flag="$tmp/notif_fail"
mkdir -p "$tmp/bin_notif"
cat > "$tmp/bin_notif/herdr" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-}" == "notification show" ]]; then
  if [[ -f "$notif_fail_flag" ]]; then
    exit 1
  fi
  printf '%s\n' "\$*" >> "$herdr_notif_log"
  exit 0
fi
if [[ "\${1:-}" != "--session" || "\${2:-}" != "spec-231" ]]; then
  exit 1
fi
shift 2
mode="\$(cat "$sess_herdr_mode" 2>/dev/null || echo ok)"
case "\${1:-} \${2:-}" in
  "workspace list")
    echo '{"result":{"workspaces":[{"workspace_id":"ws31","label":"trio HR-SESS/ravn-trio#31"},{"workspace_id":"ws32","label":"trio HR-SESS/ravn-trio#32"}]}}'
    ;;
  "agent list")
    echo '{"result":{"agents":[{"name":"pm-ravn-trio-31","agent_status":"idle","workspace_id":"ws31"},{"name":"wk-ravn-trio-31","agent_status":"running","workspace_id":"ws31"},{"name":"pm-ravn-trio-32","agent_status":"idle","workspace_id":"ws32"},{"name":"wk-ravn-trio-32","agent_status":"running","workspace_id":"ws32"}]}}'
    ;;
  "agent get")
    case "\${3:-}" in
      wk-ravn-trio-31)
        if [[ "\$mode" == "dead" ]]; then
          echo '{"result":{"agent":{"name":"wk-ravn-trio-31","agent_status":"exited","workspace_id":"ws31"}}}'
        else
          echo '{"result":{"agent":{"name":"wk-ravn-trio-31","agent_status":"running","workspace_id":"ws31"}}}'
        fi
        ;;
      wk-ravn-trio-32)
        if [[ "\$mode" == "dead32" ]]; then
          echo '{"result":{"agent":{"name":"wk-ravn-trio-32","agent_status":"exited","workspace_id":"ws32"}}}'
        else
          echo '{"result":{"agent":{"name":"wk-ravn-trio-32","agent_status":"running","workspace_id":"ws32"}}}'
        fi
        ;;
      pm-ravn-trio-*)
        echo '{"result":{"agent":{"name":"'"\${3:-}"'","agent_status":"idle","workspace_id":"ws31"}}}'
        ;;
      *) exit 1 ;;
    esac
    ;;
  "agent read")
    if [[ "\$mode" == "quota" && "\${3:-}" == "wk-ravn-trio-31" ]]; then
      echo "Error 429: rate limit exceeded"
    else
      echo "working normally"
    fi
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/bin_notif/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$notify_send_log"
EOF
cp "$tmp/bin_sess/gh" "$tmp/bin_notif/gh"
chmod +x "$tmp/bin_notif/herdr" "$tmp/bin_notif/notify-send" "$tmp/bin_notif/gh"

# 13a. herdr notification show con --sound request en sin-cuota y --sound done en terminado
: > "$herdr_notif_log"
: > "$notify_send_log"
rm -f "$notif_fail_flag"
echo "quota" > "$sess_herdr_mode"
cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<EOF
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
EOF
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess" --json >/dev/null
grep -qF -- '--sound request' "$herdr_notif_log" || fallo "esperaba --sound request en herdr notification show para sin-cuota: $(cat "$herdr_notif_log")"
[[ ! -s "$notify_send_log" ]] || fallo "no debía invocar notify-send cuando herdr notification show funcionó: $(cat "$notify_send_log")"

: > "$herdr_notif_log"
echo "dead32" > "$sess_herdr_mode"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-32": {
    "clave": "ravn-trio-32",
    "ticket": "ravn-trio-32",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-32",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "https://github.com/o/ravn-trio/pull/32",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-32 --snapshot "$snap_sess" --json >/dev/null
grep -qF -- '--sound done' "$herdr_notif_log" || fallo "esperaba --sound done en herdr notification show para terminado: $(cat "$herdr_notif_log")"

# 13b. Fallback a notify-send cuando herdr notification show falla (-u critical en muerto, -u normal en terminado)
: > "$herdr_notif_log"
: > "$notify_send_log"
touch "$notif_fail_flag"
echo "dead" > "$sess_herdr_mode"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-31": {
    "clave": "ravn-trio-31",
    "ticket": "ravn-trio-31",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-31",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --snapshot "$snap_sess" --json >/dev/null
grep -qF -- '-u critical pj-trio watch: ravn-trio-31 (muerto)' "$notify_send_log" \
  || fallo "fallback notify-send critical para muerto falló: $(cat "$notify_send_log")"

: > "$notify_send_log"
echo "dead32" > "$sess_herdr_mode"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-32": {
    "clave": "ravn-trio-32",
    "ticket": "ravn-trio-32",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-32",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "https://github.com/o/ravn-trio/pull/32",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-32 --snapshot "$snap_sess" --json >/dev/null
grep -qF -- '-u normal pj-trio watch: ravn-trio-32 (terminado)' "$notify_send_log" \
  || fallo "fallback notify-send normal para terminado falló: $(cat "$notify_send_log")"

# 13c. --no-notify silencia herdr notification show y notify-send
: > "$herdr_notif_log"
: > "$notify_send_log"
rm -f "$notif_fail_flag"
cat > "$snap_sess" <<EOF
{
  "ravn-trio-32": {
    "clave": "ravn-trio-32",
    "ticket": "ravn-trio-32",
    "estado": "en-curso",
    "estado_real": "vivo",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-32",
    "pm_herdr_status": "idle",
    "session": "spec-231",
    "pr": "https://github.com/o/ravn-trio/pull/32",
    "head": "",
    "merge_danger": "",
    "timestamp": "$now_iso"
  }
}
EOF
PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-32 --snapshot "$snap_sess" --no-notify --json >/dev/null
[[ ! -s "$herdr_notif_log" && ! -s "$notify_send_log" ]] \
  || fallo "--no-notify no debía disparar alertas: herdr=$(cat "$herdr_notif_log") notify=$(cat "$notify_send_log")"

# 13d. --loop procesa múltiples eventos consecutivos sin salir en el primero
loop_step="$tmp/loop_step"
echo "0" > "$loop_step"
cat > "$tmp/bin_notif/inotifywait" <<EOF
#!/usr/bin/env bash
s="\$(cat "$loop_step" 2>/dev/null || echo 0)"
s=\$(( s + 1 ))
echo "\$s" > "$loop_step"
if [[ "\$s" -eq 1 ]]; then
  cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<'JSON'
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "2020-01-01T00:00:00-06:00",
  "timestamp": "2020-01-01T00:00:00-06:00"
}
JSON
  exit 0
elif [[ "\$s" -eq 2 ]]; then
  cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<JSON
{
  "ticket": "ravn-trio-31",
  "estado": "hecho",
  "paso": "merge",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
JSON
  exit 0
fi
sleep 2
exit 2
EOF
chmod +x "$tmp/bin_notif/inotifywait"

echo "ok" > "$sess_herdr_mode"
cat > "$pj_sess/.trio/ravn-trio-31/status.json" <<EOF
{
  "ticket": "ravn-trio-31",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-ravn-trio-31",
  "session": "spec-231",
  "heartbeat_at": "$now_iso",
  "timestamp": "$now_iso"
}
EOF
: > "$herdr_notif_log"
rc_loop=0
out_loop="$(PATH="$tmp/bin_notif:$PATH" "$aqui/pj-trio" watch "$pj_sess" --ticket ravn-trio-31 --loop --timeout 2 --json)" || rc_loop=$?
[[ "$rc_loop" -eq 124 ]] || fallo "--loop debía seguir hasta --timeout 2 (exit 124), obtuve rc=$rc_loop ($out_loop)"
grep -q '"estado_real": "colgado"' <<<"$out_loop" || fallo "--loop no emitió primer evento (colgado): $out_loop"
grep -q '"estado": "hecho"' <<<"$out_loop" || fallo "--loop no emitió segundo evento (hecho): $out_loop"
grep -qF -- 'pj-trio watch: ravn-trio-31 (colgado)' "$herdr_notif_log" || fallo "--loop no notificó colgado con herdr notification show: $(cat "$herdr_notif_log")"
grep -qF -- '--sound request' "$herdr_notif_log" || fallo "--loop no usó --sound request para colgado: $(cat "$herdr_notif_log")"
[[ "$(wc -l < "$herdr_notif_log")" -ge 2 ]] || fallo "--loop debía notificar ambos eventos: $(cat "$herdr_notif_log")"

# 13e. Ayuda y completion incluyen --loop y --no-notify
"$aqui/pj-trio" watch --help | grep -q -- '--loop' || fallo "--help debe documentar --loop"
"$aqui/pj-trio" watch --help | grep -q -- '--no-notify' || fallo "--help debe documentar --no-notify"
comp_loop="$(bash -c '
  source "'"$aqui"'/runtime/completion/pj-trio.bash"
  COMP_WORDS=(pj-trio watch --)
  COMP_CWORD=2
  _pj_trio_completion
  printf "%s\n" "${COMPREPLY[@]}"
')"
grep -qx -- '--loop' <<<"$comp_loop" || fallo "completion de watch debe incluir --loop: $comp_loop"
grep -qx -- '--no-notify' <<<"$comp_loop" || fallo "completion de watch debe incluir --no-notify: $comp_loop"

echo "OK watch"
