#!/usr/bin/env bash

# Config del trío (kinds, identidad git), prompt del PM y helper de status.json.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

trio_cargar_config() {
    PM_KIND=""
    WK_KIND=""
    RV_KIND=""
    TRIO_GIT_NAME=""
    TRIO_GIT_EMAIL=""

    config_file="${PJ_TRIO_CONFIG:-${TRIO_SHARE_DIR}/trio.conf}"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "${project_dir}/.trio/trio.conf" ]]; then
            config_file="${project_dir}/.trio/trio.conf"
        elif [[ -f "${TRIO_ROOT}/trio.conf.example" ]]; then
            config_file="${TRIO_ROOT}/trio.conf.example"
        elif [[ -f "${project_dir}/scripts/trio.conf.example" ]]; then
            config_file="${project_dir}/scripts/trio.conf.example"
        fi
    fi

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
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
