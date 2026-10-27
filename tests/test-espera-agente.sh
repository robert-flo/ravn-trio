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

esperar_agente_listo pm-x 2>/dev/null || fallo "idle directo debería estar listo"
[[ ! -f "$tmp/notify" ]] || fallo "no debería notificar sin diálogo"

rm -f "$tmp/count"
STUB_TRUST_READS=3 esperar_agente_listo pm-x 2>/dev/null || fallo "tras cerrar el diálogo debería quedar listo"
[[ "$(wc -l <"$tmp/notify")" -eq 1 ]] || fallo "debería notificar una sola vez"
[[ "$(cat "$tmp/count")" -ge 4 ]] || fallo "debería seguir esperando mientras hay diálogo"

rm -f "$tmp/count"
if STUB_STATUS=working TRIO_READY_TIMEOUT=1 esperar_agente_listo pm-x 2>/dev/null; then
  fallo "sin idle debería vencer"
fi
echo "OK espera de agente"
