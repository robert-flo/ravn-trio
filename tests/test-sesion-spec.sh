#!/usr/bin/env bash
# Pruebas de sesión persistente herdr por spec (#125):
# - derivación/sanitización de nombre compatible con herdr --session
# - creación/reuso de sesión en modo spec y registro en status.json
# - --oneshot sin sesión persistente propia
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export PJ_TRIO_OS_PROMPT="$aqui/trio-os-prompt.md"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export TRIO_PANE_SETTLE_SECS=0 TRIO_START_RETRY_SECS=0 TRIO_READY_TIMEOUT=5 TRIO_READY_INTERVAL=0
export TRIO_SESSION_WAIT_RETRIES=10 TRIO_SESSION_WAIT_INTERVAL=0

# 1. Sanitización de nombre de sesión
# shellcheck disable=SC1091
source "$aqui/runtime/lib/trio_project.sh"
s_titulo="$(trio_nombre_sesion_spec 123 "herdr: 1 sesión persistente por spec, cierre por Orquestador")"
[[ "$s_titulo" =~ ^[A-Za-z0-9._-]+$ ]] || fallo "nombre sanitizado inválido: '$s_titulo'"
[[ "$s_titulo" == 123-herdr-1-sesion-persistente* ]] || fallo "formato inesperado: '$s_titulo'"
s_vacio="$(trio_nombre_sesion_spec 123 "")"
[[ "$s_vacio" == "spec-123" ]] || fallo "fallback vacío inesperado: '$s_vacio'"

# 2. Proyecto y miembro mínimos
git init -q -b main "$tmp/pj-demo"
git -C "$tmp/pj-demo" remote add origin "https://github.com/acme/pj-demo.git"
git init -q -b main "$tmp/miembro"
git -C "$tmp/miembro" remote add origin "https://github.com/acme/miembro.git"

mkdir -p "$tmp/bin"

cat >"$tmp/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "agents" ]]; then
  printf 'PM-pj-demo\nWK-pj-demo\nRV-pj-demo\nOS-pj-demo\n'
fi
exit 0
STUB
chmod +x "$tmp/bin/agy"

cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  ticket="$3"
  if [[ "$*" == *"title"* ]]; then
    if [[ "$ticket" == "123" ]]; then
      echo "herdr: 1 sesión persistente por spec"
    else
      echo "fix trivial"
    fi
    exit 0
  fi
  if [[ "$ticket" == "123" ]]; then
    printf 'spec\n'
  else
    printf 'ready-for-agent\n'
  fi
  exit 0
fi
exit 0
STUB
chmod +x "$tmp/bin/gh"

cat >"$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_LOG"
session=""
if [[ "${1:-}" == "--session" ]]; then
  session="$2"
  shift 2
fi
cmd="${1:-} ${2:-}"
case "$cmd" in
  "server ")
    [[ -n "$session" ]] && touch "$HERDR_STATE/srv_${session}"
    exit 0
    ;;
  "integration status")
    printf 'agy: installed\ncursor: installed\n'
    exit 0
    ;;
  "workspace list")
    if [[ -n "$session" && ! -f "$HERDR_STATE/srv_${session}" ]]; then
      echo '{"error":{"code":"server_not_running"}}'
      exit 1
    fi
    echo '{"result":{"workspaces":[]}}'
    exit 0
    ;;
  "workspace create")
    echo '{"result":{"workspace":{"workspace_id":"ws-1"},"tab":{"tab_id":"tab-pm"},"root_pane":{"pane_id":"pane-pm"}}}'
    exit 0
    ;;
  "tab create")
    lbl=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--label" ]] && lbl="$2"
      shift
    done
    echo "{\"result\":{\"tab\":{\"tab_id\":\"tab-${lbl}\"},\"root_pane\":{\"pane_id\":\"pane-${lbl}\"}}}"
    exit 0
    ;;
  "tab rename"|"pane rename")
    exit 0
    ;;
  "agent list")
    echo '{"result":{"agents":[]}}'
    exit 0
    ;;
  "pane get")
    echo '{"result":{"pane":{}}}'
    exit 0
    ;;
  "agent start"|"agent prompt")
    echo '{"result":{"ok":true}}'
    exit 0
    ;;
  "agent read")
    echo "ready"
    exit 0
    ;;
  "agent get")
    echo '{"result":{"agent":{"agent_status":"idle"}}}'
    exit 0
    ;;
  "notification show")
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/herdr"

export HERDR_STATE="$tmp/herdr_state"
mkdir -p "$HERDR_STATE"

# 3. Modo spec: crea sesión persistente, usa --session y guarda .session en status.json
export HERDR_LOG="$tmp/herdr_spec.log"
: > "$HERDR_LOG"
out_spec="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" "$tmp/pj-demo" 123 --repo "$tmp/miembro" 2>&1)"
expected_session="123-herdr-1-sesion-persistente-por-spec"

grep -q "^--session ${expected_session} server$" "$HERDR_LOG" || fallo "no inició server de sesión spec: $(cat "$HERDR_LOG")"
grep -q "^--session ${expected_session} workspace create " "$HERDR_LOG" || fallo "no creó workspace dentro de la sesión spec"
grep -q "^--session ${expected_session} agent prompt pm-miembro-123 " "$HERDR_LOG" || fallo "no envió kickoff dentro de la sesión spec"
grep -q "herdr session attach ${expected_session}" <<<"$out_spec" || fallo "salida final no indica cómo adjuntarse a la sesión"

status_file="$tmp/pj-demo/.trio/miembro-123/status.json"
[[ -f "$status_file" ]] || fallo "no se creó $status_file"
got_session="$(jq -r '.session // empty' "$status_file")"
[[ "$got_session" == "$expected_session" ]] || fallo "status.json session='$got_session', esperado='$expected_session'"

# 4. Re-ejecución de trio-status sin --session conserva .session en status.json
"$aqui/trio-status" "$tmp/pj-demo/.trio/miembro-123" en-curso wk
got_session_2="$(jq -r '.session // empty' "$status_file")"
[[ "$got_session_2" == "$expected_session" ]] || fallo "trio-status perdió .session: '$got_session_2'"

# 5. Modo --oneshot: no crea ni adjunta sesión persistente propia
export HERDR_LOG="$tmp/herdr_oneshot.log"
: > "$HERDR_LOG"
PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --oneshot "$tmp/pj-demo" 55 --repo "$tmp/miembro" >/dev/null
if grep -q -- "--session" "$HERDR_LOG"; then
  fallo "--oneshot no debe usar --session en herdr: $(cat "$HERDR_LOG")"
fi
os_status="$tmp/pj-demo/.trio/miembro-55/status.json"
[[ -f "$os_status" ]] || fallo "no se creó $os_status"
os_session="$(jq -r '.session // empty' "$os_status")"
[[ -z "$os_session" ]] || fallo "--oneshot no debe guardar .session en status.json (got '$os_session')"

echo "OK sesión persistente herdr por spec"
