#!/usr/bin/env bash

# Espera de agente listo antes del arranque.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start.

# La confianza de carpetas la gestiona la workstation (trustedWorkspaces de agy);
# pj-trio no la escribe: solo detecta el diálogo, avisa y espera una tecla.

trio_notificar() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "ravn-trio" "$*" || true
    fi
    print_warn "$*" >&2
}

# _trio_pausa_manual <agente>: pausa interactiva sin timeout. Lee una tecla del
# tty del usuario (TRIO_READY_TTY permite apuntar esa entrada a otra parte en
# las pruebas) y continúa con cualquier pulsación, sin re-chequear la pantalla.
# 0 si llegó la tecla; 1 si no hay entrada de dónde leerla.
_trio_pausa_manual() {
    local agente="$1" tty="${TRIO_READY_TTY:-/dev/tty}"
    print_warn "${agente}: esperando una tecla tuya (Enter) para continuar..." >&2
    if ! { read -rn1 <"$tty"; } 2>/dev/null; then
        print_error "no pude leer una tecla de ${tty}; sigo sin la pausa manual." >&2
        return 1
    fi
    return 0
}

# esperar_agente_listo <agente>: 0 si quedó idle sin diálogo de confianza o si
# el usuario pulsó una tecla sobre el diálogo; 1 si venció el timeout sin
# diálogo (o sin entrada de dónde leer la tecla).
# Mira `herdr agent get` (status) y `herdr agent read` (pantalla).
esperar_agente_listo() {
    local agente="$1"
    local timeout="${TRIO_READY_TIMEOUT:-180}" intervalo="${TRIO_READY_INTERVAL:-2}"
    local inicio=$SECONDS avisado=0 pausa=1 estado pantalla
    while (( SECONDS - inicio < timeout )); do
        pantalla="$(herdr agent read "$agente" 2>/dev/null | tail -n 60 || true)"
        if grep -qiE 'trust (the contents of )?this (project|folder)|Yes, I trust this folder' <<<"$pantalla"; then
            if [[ "$avisado" -eq 0 ]]; then
                trio_notificar "${agente}: agy pide confiar en la carpeta. Aceptá el diálogo en herdr y pulsá Enter para continuar."
                avisado=1
            fi
            if [[ "$pausa" -eq 1 ]] && _trio_pausa_manual "$agente"; then
                return 0
            fi
            # Sin tty de dónde leer la tecla: como antes, sondeo hasta el timeout.
            pausa=0
        else
            estado="$(herdr agent get "$agente" 2>/dev/null | jq -r '.result.agent.status // .result.status // empty' 2>/dev/null || true)"
            [[ "$estado" == idle ]] && return 0
        fi
        sleep "$intervalo"
    done
    return 1
}
