#!/usr/bin/env bash
# Pruebas de asignación de name al PM en herdr y fallback por workspace_id/pane_id en watch/fleet.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export TRIO_PANE_SETTLE_SECS=0
export TRIO_READY_INTERVAL=0
export TRIO_READY_TIMEOUT=2
export TRIO_KICKOFF_VERIFY_SECS=0

pj="$tmp/HR-DEMO"
miembro="$tmp/miembro"
git init -q "$pj"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
EOF
git init -q "$miembro"

mkdir -p "$tmp/bin"

# Mock agy: declara los agentes esperados.
cat > "$tmp/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "agents" ]]; then
  printf 'PM-HR-DEMO\nWK-HR-DEMO\nRV-HR-DEMO\nOS-HR-DEMO\n'
  exit 0
fi
exit 0
STUB
chmod +x "$tmp/bin/agy"

# Mock herdr stateful para probar start -> prompt sin -i y fallback por timeout.
cat > "$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
log="$STUB_DIR/herdr_calls.log"
echo "$*" >> "$log"

case "${1:-} ${2:-}" in
  "integration status")
    echo "agy: installed"
    ;;
  "workspace list")
    if [[ -f "$STUB_DIR/ws_exists" ]]; then
      echo '{"id":"cli:workspace:list","result":{"workspaces":[{"workspace_id":"w-24","label":"trio HR-DEMO/miembro#42"}]}}'
    else
      echo '{"id":"cli:workspace:list","result":{"workspaces":[]}}'
    fi
    ;;
  "workspace create")
    touch "$STUB_DIR/ws_exists"
    echo '{"id":"cli:workspace:create","result":{"workspace":{"workspace_id":"w-24"},"tab":{"tab_id":"t-pm"},"root_pane":{"pane_id":"w24:p1"}}}'
    ;;
  "tab create")
    lbl=""
    args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
      [[ "${args[$i]}" == "--label" ]] && lbl="${args[$((i+1))]:-}"
    done
    echo "{\"id\":\"cli:tab:create\",\"result\":{\"tab\":{\"tab_id\":\"t-${lbl}\"},\"root_pane\":{\"pane_id\":\"w24:p-${lbl}\"}}}"
    ;;
  "tab rename"|"pane rename")
    echo '{"result":{"ok":true}}'
    ;;
  "pane get")
    echo '{"result":{"pane":{}}}'
    ;;
  "agent list")
    echo '{"id":"cli:agent:list","result":{"agents":[]}}'
    ;;
  "agent start")
    name="${3:-}"
    if [[ " $* " == *" -i "* ]]; then
      echo "ERROR: -i recibido en agent start: $*" >&2
      exit 1
    fi
    if [[ -f "$STUB_DIR/pm_timeout" && "$name" == pm-* ]]; then
      touch "$STUB_DIR/pm_unnamed_ready"
      echo '{"error":{"code":"timeout","message":"timed out waiting for interactive readiness"}}'
      exit 1
    fi
    touch "$STUB_DIR/agent_${name}_ready"
    echo "{\"id\":\"cli:agent:start\",\"result\":{\"agent\":{\"name\":\"$name\",\"interactive_ready\":true,\"agent_status\":\"idle\"}}}"
    ;;
  "agent get")
    target="${3:-}"
    status_val="idle"
    [[ -f "$STUB_DIR/agent_working" ]] && status_val="working"
    if [[ -f "$STUB_DIR/agent_${target}_ready" ]]; then
      echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"$target\",\"agent_status\":\"$status_val\",\"interactive_ready\":true,\"workspace_id\":\"w-24\",\"pane_id\":\"w24:p1\"}}}"
      exit 0
    fi
    if [[ "$target" == "w24:p1" && -f "$STUB_DIR/pm_unnamed_ready" ]]; then
      echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"agent_status\":\"$status_val\",\"interactive_ready\":true,\"workspace_id\":\"w-24\",\"pane_id\":\"w24:p1\"}}}"
      exit 0
    fi
    echo '{"error":{"code":"agent_not_found"}}'
    exit 1
    ;;
  "agent read")
    echo ">"
    ;;
  "agent prompt")
    target="${3:-}"
    if [[ "$target" == pm-* && ! -f "$STUB_DIR/agent_${target}_ready" ]]; then
      echo '{"error":{"code":"agent_not_found"}}'
      exit 1
    fi
    touch "$STUB_DIR/agent_working"
    echo '{"result":{"ok":true}}'
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$tmp/bin/herdr"

# 1. Arranque normal: PM arranca sin -i, queda registrado con name y recibe kickoff vía herdr agent prompt.
export STUB_DIR="$tmp/s1"
mkdir -p "$STUB_DIR"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$pj" 42 --repo "$miembro" >/dev/null
grep -q '^agent start pm-miembro-42 --kind agy --pane w24:p1 -- --agent PM-HR-DEMO' "$STUB_DIR/herdr_calls.log" \
  || fallo "PM no arrancó con herdr agent start esperado"
if grep -q -- ' -i ' "$STUB_DIR/herdr_calls.log"; then
  fallo "no debía pasar -i a agy en herdr agent start"
fi
grep -q '^agent prompt pm-miembro-42 Lee y segui al pie de la letra las instrucciones de arranque del archivo ' "$STUB_DIR/herdr_calls.log" \
  || fallo "no envió kickoff de una línea vía herdr agent prompt pm-miembro-42"
[[ -f "$pj/.trio/miembro-42/status.json" ]] || fallo "no escribió status.json tras kickoff"

# 2. Fallback si herdr agent start devuelve timeout (sin name): espera y manda prompt al pane_id.
rm -rf "$pj/.trio/miembro-42"
export STUB_DIR="$tmp/s2"
mkdir -p "$STUB_DIR"
touch "$STUB_DIR/pm_timeout"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$pj" 42 --repo "$miembro" >/dev/null 2>&1
grep -q '^agent prompt w24:p1 Lee y segui al pie de la letra las instrucciones de arranque del archivo ' "$STUB_DIR/herdr_calls.log" \
  || fallo "en timeout sin name debía hacer fallback a herdr agent prompt w24:p1"
[[ -f "$pj/.trio/miembro-42/status.json" ]] || fallo "no escribió status.json tras fallback"

# 3. watch y fleet: cuando el PM no aparece por name en herdr agent get, resuelven por workspace_id / pane_id.
pj2="$tmp/HR-WATCH"
git init -q "$pj2"
cat > "$pj2/proyecto.yml" <<'EOF'
proyecto: HR-WATCH
EOF
mkdir -p "$pj2/.trio/ravn-trio-21"
cat > "$pj2/.trio/ravn-trio-21/status.json" <<'EOF'
{
  "ticket": "ravn-trio-21",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "2026-11-22T10:00:00-06:00"
}
EOF

mkdir -p "$tmp/bin_wf"
cat > "$tmp/bin_wf/herdr" <<'STUB'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "agent get")
    echo '{"error":{"code":"agent_not_found"}}'
    exit 1
    ;;
  "workspace list")
    echo '{"id":"cli:workspace:list","result":{"workspaces":[{"workspace_id":"w24","label":"trio HR-WATCH/ravn-trio#21"}]}}'
    ;;
  "pane list")
    echo '{"id":"cli:pane:list","result":{"panes":[{"agent":"agy","agent_status":"idle","label":"PM-21","pane_id":"w24:p1","workspace_id":"w24"},{"agent":"agy","agent_status":"working","label":"WK-21","pane_id":"w24:p2","workspace_id":"w24"}]}}'
    ;;
  "agent list")
    echo '{"id":"cli:agent:list","result":{"agents":[{"agent":"agy","agent_status":"idle","pane_id":"w24:p1","workspace_id":"w24"}]}}'
    ;;
  *)
    exit 1
    ;;
esac
STUB
cat > "$tmp/bin_wf/inotifywait" <<'STUB'
#!/usr/bin/env bash
sleep 1
exit 2
STUB
chmod +x "$tmp/bin_wf/herdr" "$tmp/bin_wf/inotifywait"

# 3a. watch no debe salir prematuramente con pm=unknown; debe agotar el timeout (124) y guardar pm_herdr_status=idle.
snap="$tmp/watch_snap.json"
rc=0
out_watch="$(PATH="$tmp/bin_wf:/usr/bin:/bin" PJ_TRIO_WATCH_INTERVAL=1 "$aqui/pj-trio" watch "$pj2" --ticket ravn-trio-21 --snapshot "$snap" --timeout 1 --json)" || rc=$?
[[ "$rc" -eq 124 ]] || fallo "watch salió prematuramente (rc=$rc): $out_watch"
jq -e '.status == "timeout"' <<<"$out_watch" >/dev/null || fallo "watch debía terminar en timeout, obtuvo: $out_watch"
jq -e '.["ravn-trio-21"].pm_herdr_status == "idle" and .["ravn-trio-21"].pm_agent == "w24:p1"' "$snap" >/dev/null \
  || fallo "snapshot no resolvió pm_herdr_status=idle por pane_id: $(cat "$snap")"

# 3b. fleet debe reportar pm_herdr_status=idle y workspace_id=w24 (no cerrado).
out_fleet="$(PATH="$tmp/bin_wf:/usr/bin:/bin" "$aqui/pj-trio" fleet "$pj2" --json)"
jq -e '.[] | select(.clave == "ravn-trio-21") | .pm_herdr_status == "idle" and .workspace_id == "w24"' <<<"$out_fleet" >/dev/null \
  || fallo "fleet no resolvió PM sin name por workspace_id/pane_id: $out_fleet"

echo "OK pm name herdr"
