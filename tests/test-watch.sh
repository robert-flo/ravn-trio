#!/usr/bin/env bash
# Pruebas de `pj-trio watch`: diff contra --snapshot, cambio de paso/estado, blocked, timeout y alias w.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

pj="$tmp/HR-DEMO"
git init -q "$pj"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
EOF

mkdir -p "$pj/.trio/ravn-trio-21"
cat > "$pj/.trio/ravn-trio-21/status.json" <<'EOF'
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "2026-11-17T09:00:00-06:00"
}
EOF

mkdir -p "$tmp/bin_stubs"
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
echo "noop" > "$inotify_mode"

cat > "$tmp/bin_stubs/inotifywait" <<EOF
#!/usr/bin/env bash
mode="\$(cat "$inotify_mode" 2>/dev/null || echo noop)"
case "\$mode" in
  change_paso)
    cat > "$pj/.trio/ravn-trio-21/status.json" <<'JSON'
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "rv",
  "timestamp": "2026-11-17T09:05:00-06:00"
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

# 1. Diff inmediato contra --snapshot previo (sin entrar al loop de inotifywait)
snap="$tmp/snap.json"
cat > "$snap" <<'EOF'
{
  "ravn-trio-21": {
    "clave": "ravn-trio-21",
    "ticket": "ravn-trio-21",
    "estado": "en-curso",
    "paso": "plan",
    "pm_agent": "pm-ravn-trio-21",
    "pm_herdr_status": "running",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "2026-11-17T08:55:00-06:00"
  }
}
EOF

out_snap="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --json)"
jq -e '.status == "changed" and (.events | length == 1) and .events[0].tipo == "paso" and .events[0].paso == "wk"' <<<"$out_snap" >/dev/null \
  || fallo "diff contra --snapshot inesperado: $out_snap"
jq -e '.["ravn-trio-21"].paso == "wk"' "$snap" >/dev/null \
  || fallo "snapshot no se actualizó tras diff"

# 2. Detección de cambio de paso vía inotifywait y alias w
echo "change_paso" > "$inotify_mode"
out_paso="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" w "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and .events[0].tipo == "paso" and .events[0].prev_paso == "wk" and .events[0].paso == "rv"' <<<"$out_paso" >/dev/null \
  || fallo "detección de cambio de paso falló: $out_paso"

# 3. Detección de needs-roberto con captura de últimas 25 líneas de herdr agent read
echo "change_needs_roberto" > "$inotify_mode"
out_nr="$(PATH="$tmp/bin_stubs:$PATH" "$aqui/pj-trio" watch "$pj" --snapshot "$snap" --timeout 10 --json)"
jq -e '.status == "changed" and .events[0].tipo == "estado" and .events[0].estado == "needs-roberto"' <<<"$out_nr" >/dev/null \
  || fallo "detección de needs-roberto falló: $out_nr"
tail_lines="$(jq -r '.events[0].tail' <<<"$out_nr" | wc -l)"
[[ "$tail_lines" -eq 25 ]] || fallo "esperaba 25 líneas en tail, obtuve $tail_lines"
jq -r '.events[0].tail' <<<"$out_nr" | grep -q 'linea-30 de pm-ravn-trio-21' \
  || fallo "tail no contiene la última línea esperada"

# 4. Detección de blocked en herdr agent get dentro del loop sin cambios en status.json
cat > "$pj/.trio/ravn-trio-21/status.json" <<'EOF'
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "2026-11-17T09:15:00-06:00"
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
cat > "$snap" <<'EOF'
{
  "ravn-trio-21": {
    "clave": "ravn-trio-21",
    "ticket": "ravn-trio-21",
    "estado": "en-curso",
    "paso": "wk",
    "pm_agent": "pm-ravn-trio-21",
    "pm_herdr_status": "running",
    "pr": "",
    "head": "",
    "merge_danger": "",
    "timestamp": "2026-11-17T09:15:00-06:00"
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

echo "OK watch"
