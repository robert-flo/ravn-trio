#!/usr/bin/env bash
# Prueba con stubs de herdr/notify-send: espera de agente listo y diálogo de confianza de agy.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
# herdr stub: las primeras N lecturas muestran el diálogo de confianza; luego idle.
cat >"$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
c="$STUB_DIR/count"; n=$(cat "$c" 2>/dev/null || echo 0)
case "$1 $2" in
  "agent read") n=$((n+1)); echo "$n" >"$c"
     if (( n <= ${STUB_TRUST_READS:-0} )); then printf 'Do you trust the contents of this project?\n> Yes, I trust this folder\n'; else echo '>'; fi ;;
  "agent get") echo "{\"result\":{\"agent\":{\"status\":\"${STUB_STATUS:-idle}\"}}}" ;;
esac
STUB
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "$*" >>"$STUB_DIR/notify"\n' >"$tmp/bin/notify-send"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" STUB_DIR="$tmp" TRIO_READY_INTERVAL=0

# shellcheck disable=SC1091
source "$aqui/runtime/lib/presentation.sh"
# shellcheck disable=SC1091
source "$aqui/runtime/lib/trio_agy.sh"
export -f esperar_agente_listo trio_notificar print_warn print_error
declare -F _trio_pausa_manual >/dev/null 2>&1 && export -f _trio_pausa_manual

# tty de pruebas: fifo sin datos; si el código pide una tecla cuando no debe,
# se queda colgado y el timeout de la prueba lo mata.
mkfifo "$tmp/tty"

# 1. Control positivo: agente idle y sin diálogo → listo de una, sin pausa.
timeout 10 env TRIO_READY_TTY="$tmp/tty" bash -c 'esperar_agente_listo pm-x' 2>/dev/null \
  || fallo "idle directo debería estar listo sin pedir tecla"
[[ ! -f "$tmp/notify" ]] || fallo "no debería notificar sin diálogo"

# 2. Diálogo de confianza visible → aviso + pausa manual: sin tecla no avanza
#    solo (el timeout de 1 s no lo mata) y con la tecla continúa.
rm -f "$tmp/count" "$tmp/notify"
export TRIO_READY_TTY="$tmp/tty" TRIO_READY_TIMEOUT=1 STUB_TRUST_READS=999
esperar_agente_listo pm-x >/dev/null 2>"$tmp/err" & pid=$!
sleep 2
# El job muerto queda zombie hasta el wait: kill -0 seguiría respondiendo.
estado_ps="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
[[ "$estado_ps" == *Z* || -z "$estado_ps" ]] \
  && fallo "con diálogo debería seguir esperando la tecla, no vencer solo"
printf '\n' >"$tmp/tty"
wait "$pid" || fallo "tras la tecla debería continuar"
[[ "$(wc -l <"$tmp/notify")" -eq 1 ]] || fallo "debería notificar una sola vez"
grep -q "pm-x" "$tmp/notify" || fallo "el aviso debería nombrar al agente"
grep -qi "enter" "$tmp/err" || fallo "la pausa debería pedir Enter"
unset TRIO_READY_TTY TRIO_READY_TIMEOUT STUB_TRUST_READS

# 3. Sin diálogo y sin idle: no toca la pausa y vence al timeout como antes.
rm -f "$tmp/count" "$tmp/notify"
rc3=0
timeout 10 env STUB_STATUS=working TRIO_READY_TTY="$tmp/tty" TRIO_READY_TIMEOUT=1 \
  bash -c 'esperar_agente_listo pm-x' 2>/dev/null || rc3=$?
[[ "$rc3" -eq 1 ]] || fallo "sin idle debería vencer al timeout (rc=$rc3)"

# 4. Diálogo pero sin tty de dónde leer la tecla: no se cuelga; sondea y vence.
rm -f "$tmp/count"
rc4=0
timeout 10 env STUB_TRUST_READS=999 TRIO_READY_TTY="$tmp/no-existe" TRIO_READY_TIMEOUT=1 \
  bash -c 'esperar_agente_listo pm-x' 2>/dev/null || rc4=$?
[[ "$rc4" -ne 124 ]] || fallo "sin tty no debería colgarse"
echo "OK espera de agente"
