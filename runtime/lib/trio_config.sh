#!/usr/bin/env bash

# Config del trío (kinds, identidad git), prompt del PM y helper de status.json.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

trio_cargar_config() {
    PM_KIND=""
    WK_KIND=""
    RV_KIND=""
    TRIO_GIT_NAME=""
    TRIO_GIT_EMAIL=""

    # Capas (la última gana): defaults del sistema → override en /zt → repo.
    # PJ_TRIO_CONFIG, si está, reemplaza todas las capas. Nada en $HOME.
    trio_config_capas=()
    if [[ -n "${PJ_TRIO_CONFIG:-}" ]]; then
        trio_config_capas=("$PJ_TRIO_CONFIG")
    else
        local defaults=""
        for c in "${TRIO_SHARE_DIR}/trio.conf" "${TRIO_ROOT}/trio.conf.example" "${TRIO_SHARE_DIR}/trio.conf.example"; do
            if [[ -f "$c" ]]; then
                defaults="$c"
                break
            fi
        done
        [[ -n "$defaults" ]] && trio_config_capas+=("$defaults")
        [[ -f "${TRIO_OVERRIDE_DIR}/trio.conf" ]] && trio_config_capas+=("${TRIO_OVERRIDE_DIR}/trio.conf")
        [[ -f "${project_dir}/.trio/trio.conf" ]] && trio_config_capas+=("${project_dir}/.trio/trio.conf")
    fi

    local f
    for f in "${trio_config_capas[@]}"; do
        if [[ -f "$f" ]]; then
            # shellcheck source=/dev/null
            source "$f"
        fi
    done
    config_file=""
    if ((${#trio_config_capas[@]})); then
        config_file="${trio_config_capas[*]}"
    fi
}

trio_localizar_recursos() {
    prompt_template="${PJ_TRIO_PM_PROMPT:-}"
    if [[ -z "$prompt_template" ]]; then
        for c in ${TRIO_SHARE_DIR}/trio-pm-prompt.md "${TRIO_ROOT}/trio-pm-prompt.md"; do
            if [[ -f "$c" ]]; then
                prompt_template="$c"
                break
            fi
        done
    fi

    # Helper de status.json: junto a pj-trio, en ${TRIO_SHARE_DIR} o en el PATH.
    trio_status="${TRIO_ROOT}/trio-status"
    if [[ ! -x "$trio_status" ]]; then
        if [[ -x ${TRIO_SHARE_DIR}/trio-status ]]; then
            trio_status=${TRIO_SHARE_DIR}/trio-status
        else
            trio_status="$(command -v trio-status || echo trio-status)"
        fi
    fi
}

renderizar_kickoff() {
    if [[ -z "$prompt_template" || ! -f "$prompt_template" ]]; then
        print_error "no se encontró trio-pm-prompt.md (definí PJ_TRIO_PM_PROMPT)." >&2
        return 1
    fi
    local t
    t="$(cat "$prompt_template")"
    t="${t//\{\{PROYECTO\}\}/$project_name}"
    t="${t//\{\{PROYECTO_DIR\}\}/$project_dir}"
    t="${t//\{\{TICKET\}\}/$ticket}"
    t="${t//\{\{MIEMBRO_DIR\}\}/$miembro_dir}"
    t="${t//\{\{TRIO_DIR\}\}/$trio_dir}"
    t="${t//\{\{AGENTE_PM\}\}/$agent_pm}"
    t="${t//\{\{AGENTE_WK\}\}/$agent_wk}"
    t="${t//\{\{AGENTE_RV\}\}/$agent_rv}"
    t="${t//\{\{TRIO_STATUS\}\}/$trio_status}"
    printf '%s\n' "$t"
}
