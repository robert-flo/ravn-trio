#!/usr/bin/env bash

# Espera de agente listo antes del arranque.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start.

# La confianza de carpetas la gestiona la workstation (trustedWorkspaces de agy);
# pj-trio no la escribe: solo detecta el diálogo, avisa y espera.

trio_notificar() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "ravn-trio" "$*" || true
    fi
    print_warn "$*" >&2
}

# esperar_agente_listo <agente>: 0 si quedó idle sin diálogo de confianza; 1 si venció.
# Mira `herdr agent get` (status) y `herdr agent read` (pantalla).
esperar_agente_listo() {
    local agente="$1"
    local timeout="${TRIO_READY_TIMEOUT:-180}" intervalo="${TRIO_READY_INTERVAL:-2}"
    local inicio=$SECONDS avisado=0 estado pantalla
    while (( SECONDS - inicio < timeout )); do
        pantalla="$(herdr agent read "$agente" 2>/dev/null | tail -n 60 || true)"
        if grep -qiE 'trust (the contents of )?this (project|folder)|Yes, I trust this folder' <<<"$pantalla"; then
            if [[ "$avisado" -eq 0 ]]; then
                trio_notificar "${agente}: agy pide confiar en la carpeta. Aceptá en herdr; el arranque se envía al cerrar el diálogo."
                avisado=1
            fi
        else
            estado="$(herdr agent get "$agente" 2>/dev/null | jq -r '.result.agent.status // .result.status // empty' 2>/dev/null || true)"
            [[ "$estado" == idle ]] && return 0
        fi
        sleep "$intervalo"
    done
    return 1
}
