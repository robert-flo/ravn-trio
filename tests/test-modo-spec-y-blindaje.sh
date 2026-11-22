#!/usr/bin/env bash
# Prueba con mocks de gh y herdr: modo spec (flag y autodetect), blindaje de
# arranque en trio_herdr.sh y manejo de idle sin wk.md/rv.md en kickoff.md.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Proyecto y miembro mínimos
git init -q -b main "$tmp/remoto.git" --bare
git init -q -b main "$tmp/miembro"
git -C "$tmp/miembro" commit -q --allow-empty -m inicio
git -C "$tmp/miembro" remote add origin "$tmp/remoto.git"
git -C "$tmp/miembro" push -q origin main main:116-spec
git init -q "$tmp/pj-demo"
git -C "$tmp/pj-demo" remote add origin "https://github.com/acme/pj-demo.git"

mkdir -p "$tmp/bin"

# Mock de gh: devuelve etiqueta 'spec' solo para el ticket 99.
cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "issue view" ]]; then
  ticket="$3"
  if [[ "$ticket" == "99" ]]; then
    printf 'spec\nenhancement\n'
  else
    printf 'ready-for-agent\n'
  fi
  exit 0
fi
exit 0
STUB
chmod +x "$tmp/bin/gh"

# 1. Modo spec por flag explícito --spec
k_flag="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --print-kickoff --spec "$tmp/pj-demo" 42 --repo "$tmp/miembro")"
grep -q '{{' <<<"$k_flag" && fallo "quedan placeholders con --spec"
grep -q '/implement-spec' <<<"$k_flag" || fallo "modo spec debe instruir /implement-spec al WK"
grep -q '/code-review' <<<"$k_flag" || fallo "modo spec debe instruir /code-review por sub-issue"
grep -q 'APRUEBO <sha>' <<<"$k_flag" || fallo "modo spec debe conservar paso RV / APRUEBO"
grep -q 'Merge Danger' <<<"$k_flag" || fallo "modo spec debe evaluar Merge Danger"

# 2. Modo spec por detección automática vía etiqueta 'spec' en gh issue view
k_auto="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 99 --repo "$tmp/miembro")"
grep -q '/implement-spec' <<<"$k_auto" || fallo "autodetect con etiqueta spec debe activar modo spec"

# 3. Sin etiqueta 'spec' ni --spec: mantiene modo unitario normal
k_unit="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro")"
grep -q '/implement-spec' <<<"$k_unit" && fallo "ticket unitario no debe activar modo spec"
grep -q 'git-create-worktree' <<<"$k_unit" || fallo "ticket unitario debe mantener flujo de worktree único"

# 4. Compatibilidad con --spec + --base y rechazo de --spec --oneshot
k_base="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --print-kickoff --spec "$tmp/pj-demo" 42 --repo "$tmp/miembro" --base 116-spec)"
grep -q 'origin/116-spec' <<<"$k_base" || fallo "--spec con --base debe respetar la base explícita"
grep -q '42-<slug>' <<<"$k_base" || fallo "--spec con --base no debe pisar la rama del spec 42-<slug>"
grep -q -- "--base '116-spec'" <<<"$k_base" || fallo "--spec con --base debe apuntar el PR final a 116-spec"
if "$aqui/pj-trio" --print-kickoff --spec --oneshot "$tmp/pj-demo" 42 --repo "$tmp/miembro" >/dev/null 2>&1; then
  fallo "no debería aceptar --spec y --oneshot juntos"
fi

# 5. Texto de manejo de idle sin archivo de entrega (wk.md / rv.md) en kickoff.md
for k in "$k_flag" "$k_unit"; do
  grep -q 'Spec Code Reviewer' <<<"$k" || fallo "kickoff.md debe mencionar subagentes como Spec Code Reviewer"
  grep -q 'herdr agent read' <<<"$k" || fallo "kickoff.md debe indicar verificar actividad con herdr agent read"
  grep -q 'gh pr list' <<<"$k" || fallo "kickoff.md debe indicar verificar actividad con gh pr list"
  grep -q 'needs-roberto' <<<"$k" || fallo "kickoff.md debe explicar qué hacer antes de escalar a needs-roberto"
done

# 6. Blindaje de herdr en trio_herdr.sh: reintento ante 'no longer owns the target terminal'
cat >"$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane get") echo '{"result":{"pane":{}}}' ;;
  "pane read") echo "zsh: ready"; echo "ultima salida del pane de prueba" ;;
  "agent start")
    c="$STUB_DIR/start_count"
    n=$(cat "$c" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" >"$c"
    if [[ "$n" -le "${STUB_FAIL_COUNT:-1}" ]]; then
      echo '{"error":{"code":"terminal_error","message":"no longer owns the target terminal"}}'
      exit 1
    fi
    echo '{"result":{"ok":true}}'
    exit 0
    ;;
esac
STUB
chmod +x "$tmp/bin/herdr"

# shellcheck disable=SC1091
source "$aqui/runtime/lib/presentation.sh"
# shellcheck disable=SC1091
source "$aqui/runtime/lib/trio_project.sh"
# shellcheck disable=SC1091
source "$aqui/runtime/lib/trio_config.sh"
# shellcheck disable=SC1091
source "$aqui/runtime/lib/trio_herdr.sh"

export PATH="$tmp/bin:/usr/bin:/bin" STUB_DIR="$tmp"
export TRIO_PANE_SETTLE_SECS=0 TRIO_START_RETRY_SECS=0

project_name="pj-demo"
project_dir="$tmp/pj-demo"
repo_path=""
ticket="42"
trio_dir="$tmp/pj-demo/.trio/42"
kickoff=0
agent_pm="pm-pj-demo"
agent_wk="wk-pj-demo"
agent_rv="rv-pj-demo"
agent_os="os-pj-demo"

# 6a. Falla 1 vez con 'no longer owns the target terminal', reintenta y tiene éxito.
rm -f "$tmp/start_count"
pm_fallo_inicio=0
STUB_FAIL_COUNT=1 iniciar_agente_rol "PM" "pane-1" "agy" 2>"$tmp/err_retry_ok"
[[ "$(cat "$tmp/start_count")" -eq 2 ]] || fallo "debería reintentar 1 vez (llamadas=$(cat "$tmp/start_count"))"
[[ "$pm_fallo_inicio" -eq 0 ]] || fallo "si el reintento tiene éxito, pm_fallo_inicio debe quedar en 0"

# 6b. Falla 2 veces: no reintenta más y captura la última salida del pane.
rm -f "$tmp/start_count"
pm_fallo_inicio=0
STUB_FAIL_COUNT=99 iniciar_agente_rol "PM" "pane-1" "agy" 2>"$tmp/err_retry_fail"
[[ "$(cat "$tmp/start_count")" -eq 2 ]] || fallo "debería intentar máximo 2 veces (llamadas=$(cat "$tmp/start_count"))"
[[ "$pm_fallo_inicio" -eq 1 ]] || fallo "si vuelve a fallar, pm_fallo_inicio debe quedar en 1"
grep -q 'ultima salida del pane de prueba' "$tmp/err_retry_fail" || fallo "si vuelve a fallar debe capturar la última salida del pane"

echo "OK modo spec y blindaje herdr"
