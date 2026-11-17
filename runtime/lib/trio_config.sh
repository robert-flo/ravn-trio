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
    # Base del worktree y del PR: la rama del spec (--base) o la rama por defecto.
    # gh_pr_base: el --base explícito de gh pr create (vacío en un trivial: gh usa la rama por defecto).
    local base_ref="origin/HEAD" base_pr="la rama por defecto" gh_pr_base=""
    # Quién mergea (ADR 0018 de pj-template, regla de fleet): un sub-issue lo mergea
    # el WK a la rama del spec sin RV; un trivial lo revisa RV y lo mergea el PM.
    local wk_merge="" nota_subissue=""
    if [[ -n "${base_rama:-}" ]]; then
        base_ref="origin/${base_rama}"
        base_pr="${base_rama}"
        gh_pr_base=" --base '${base_rama}'"
        wk_merge=" Es un sub-issue: con CI verde y code-review limpio, mergeá vos tu PR a ${base_rama} con gh pr merge <pr> -R ${ticket_repo:-} --squash --delete-branch --match-head-commit <sha-verde> y anotá el sha del merge en wk.md."
        nota_subissue="Este ticket es un sub-issue (base ${base_rama}): no hay paso RV ni merge tuyo. El WK mergea su PR a la rama del spec (ADR 0018 de pj-template). Confirmá en GitHub que quedó mergeado (\`gh pr view <pr> -R ${ticket_repo:-} --json state,mergeCommit\`) y saltá al paso 7. El PR final de la rama del spec lo revisa RV y lo mergeás vos."
    fi
    local t
    t="$(cat "$prompt_template")"
    t="${t//\{\{PROYECTO\}\}/$project_name}"
    t="${t//\{\{PROYECTO_DIR\}\}/$project_dir}"
    t="${t//\{\{TICKET\}\}/$ticket}"
    t="${t//\{\{TICKET_REPO\}\}/${ticket_repo:-}}"
    t="${t//\{\{MIEMBRO_DIR\}\}/$miembro_dir}"
    t="${t//\{\{TRIO_DIR\}\}/$trio_dir}"
    t="${t//\{\{BASE_REF\}\}/"$base_ref"}"
    t="${t//\{\{BASE_PR\}\}/"$base_pr"}"
    t="${t//\{\{GH_PR_BASE\}\}/"$gh_pr_base"}"
    t="${t//\{\{WK_MERGE\}\}/"$wk_merge"}"
    t="${t//\{\{NOTA_SUBISSUE\}\}/"$nota_subissue"}"
    t="${t//\{\{WT_RAIZ\}\}/"${wt_raiz:-}"}"
    t="${t//\{\{MIEMBRO_SLUG\}\}/"${miembro_slug:-}"}"
    t="${t//\{\{AGENTE_PM\}\}/$agent_pm}"
    t="${t//\{\{AGENTE_WK\}\}/$agent_wk}"
    t="${t//\{\{AGENTE_RV\}\}/$agent_rv}"
    t="${t//\{\{TRIO_STATUS\}\}/$trio_status}"
    t="${t//\{\{WORKSPACE_NOMBRE\}\}/${ws_label:-}}"
    printf '%s\n' "$t"
}
