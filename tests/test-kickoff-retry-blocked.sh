#!/usr/bin/env bash
# Pruebas de verificación post-kickoff, limpieza/reintento con Ctrl+U y marcado blocked en status.json.
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

cat > "$tmp/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "agents" ]]; then
  printf 'PM-HR-DEMO\nWK-HR-DEMO\nRV-HR-DEMO\nOS-HR-DEMO\n'
  exit 0
fi
exit 0
STUB
chmod +x "$tmp/bin/agy"

cat > "$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$STUB_DIR/herdr_calls.log"

case "${1:-} ${2:-}" in
  "integration status")
    echo "agy: installed"
    ;;
  "workspace list")
    echo '{"id":"cli:workspace:list","result":{"workspaces":[]}}'
    ;;
  "workspace create")
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
    echo "{\"id\":\"cli:agent:start\",\"result\":{\"agent\":{\"name\":\"$name\",\"interactive_ready\":true,\"agent_status\":\"idle\"}}}"
    ;;
  "agent get")
    target="${3:-}"
    echo "{\"id\":\"cli:agent:get\",\"result\":{\"agent\":{\"name\":\"$target\",\"agent_status\":\"idle\",\"interactive_ready\":true,\"workspace_id\":\"w-24\",\"pane_id\":\"w24:p1\"}}}"
    ;;
  "agent prompt")
    n=0
    [[ -f "$STUB_DIR/prompt_count" ]] && n="$(cat "$STUB_DIR/prompt_count")"
    n=$((n + 1))
    echo "$n" > "$STUB_DIR/prompt_count"
    echo '{"result":{"ok":true}}'
    ;;
  "agent read")
    n=0
    [[ -f "$STUB_DIR/prompt_count" ]] && n="$(cat "$STUB_DIR/prompt_count")"
    if [[ -n "${STUB_ACCEPT_ON_ATTEMPT:-}" ]] && (( n >= STUB_ACCEPT_ON_ATTEMPT )); then
      printf 'Generating...\n'
    else
      printf '> Lee y segui al pie de la letra...\n'
    fi
    ;;
  "agent send-keys")
    echo '{"result":{"ok":true}}'
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$tmp/bin/herdr"

# 1. Primer prompt queda atascado en `>`, Ctrl+U limpia y el 2do intento muestra Generating... -> en-curso.
export STUB_DIR="$tmp/s_retry"
mkdir -p "$STUB_DIR"
STUB_ACCEPT_ON_ATTEMPT=2 PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$pj" 42 --repo "$miembro" >/dev/null 2>"$tmp/err1"

[[ "$(cat "$STUB_DIR/prompt_count")" -eq 2 ]] || fallo "debía reintentar una vez (prompt_count=$(cat "$STUB_DIR/prompt_count"))"
grep -q '^agent send-keys pm-miembro-42 ctrl+u$' "$STUB_DIR/herdr_calls.log" \
  || fallo "debía limpiar la línea con ctrl+u antes de reintentar: $(cat "$STUB_DIR/herdr_calls.log")"
jq -e '.estado == "en-curso" and .paso == "plan"' "$pj/.trio/miembro-42/status.json" >/dev/null \
  || fallo "tras reintento exitoso status.json debía quedar en-curso: $(cat "$pj/.trio/miembro-42/status.json")"

# 2. Si agota los reintentos (nunca sale de idle ni muestra Generating...), marca status.json como blocked.
rm -rf "$pj/.trio/miembro-42"
export STUB_DIR="$tmp/s_blocked"
mkdir -p "$STUB_DIR"
STUB_ACCEPT_ON_ATTEMPT=99 PATH="$tmp/bin:$PATH" "$aqui/pj-trio" "$pj" 42 --repo "$miembro" >/dev/null 2>"$tmp/err2"

[[ "$(cat "$STUB_DIR/prompt_count")" -eq 3 ]] || fallo "debía intentar 1 inicial + 2 reintentos (prompt_count=$(cat "$STUB_DIR/prompt_count"))"
[[ "$(grep -c '^agent send-keys pm-miembro-42 ctrl+u$' "$STUB_DIR/herdr_calls.log")" -eq 2 ]] \
  || fallo "debía enviar ctrl+u 2 veces entre reintentos"
jq -e '.estado == "blocked" and .paso == "plan" and (.error | length > 0)' "$pj/.trio/miembro-42/status.json" >/dev/null \
  || fallo "tras agotar reintentos status.json debía quedar blocked con error: $(cat "$pj/.trio/miembro-42/status.json")"

# 3. pj-trio watch despierta de inmediato (exit 0) cuando status.json está en blocked.
rc_watch=0
out_watch="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" watch "$pj" --ticket miembro-42 --timeout 1 --json)" || rc_watch=$?
[[ "$rc_watch" -eq 0 ]] || fallo "watch debía despertar inmediato con estado=blocked (rc=$rc_watch): $out_watch"
jq -e '.status == "changed" and .events[0].estado == "blocked"' <<<"$out_watch" >/dev/null \
  || fallo "watch debía emitir evento con estado=blocked: $out_watch"

echo "OK kickoff retry y blocked"
