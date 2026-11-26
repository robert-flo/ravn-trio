#!/usr/bin/env bash

# Config del trío (kinds, identidad git), prompt del PM y helper de status.json.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

trio_cargar_config() {
    PM_KIND=""
    WK_KIND=""
    RV_KIND=""
    OS_KIND=""
    TRIO_GIT_NAME=""
    TRIO_GIT_EMAIL=""
    TRIO_STALE_MINUTES=""
    TRIO_LEASE_MINUTES=""
    TRIO_QUOTA_PATTERNS=""

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
    [[ -n "$OS_KIND" ]] || OS_KIND="${PM_KIND:-agy}"
    [[ -n "${TRIO_STALE_MINUTES:-}" ]] || TRIO_STALE_MINUTES="15"
    [[ -n "${TRIO_LEASE_MINUTES:-}" ]] || TRIO_LEASE_MINUTES="15"
    [[ -n "${TRIO_QUOTA_PATTERNS:-}" ]] || TRIO_QUOTA_PATTERNS="rate limit|rate_limit|quota exceeded|resource exhausted|resource_exhausted|too many requests|429|usage limit|insufficient_quota|out of quota|sin cuota"
    config_file=""
    if ((${#trio_config_capas[@]})); then
        config_file="${trio_config_capas[*]}"
    fi
}

trio_localizar_recursos() {
    prompt_template="${PJ_TRIO_PM_PROMPT:-}"
    if [[ "${modo_oneshot:-0}" -eq 1 ]]; then
        prompt_template="${PJ_TRIO_OS_PROMPT:-}"
        if [[ -z "$prompt_template" ]]; then
            for c in "${TRIO_ROOT}/trio-os-prompt.md" "${TRIO_SHARE_DIR}/trio-os-prompt.md"; do
                if [[ -f "$c" ]]; then
                    prompt_template="$c"
                    break
                fi
            done
        fi
    fi
    if [[ -z "$prompt_template" ]]; then
        for c in "${TRIO_ROOT}/trio-pm-prompt.md" "${TRIO_SHARE_DIR}/trio-pm-prompt.md"; do
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

trio_cursor_rule_ref() {
    local rule="$1" slug
    slug="$(sanear_nombre "$project_name")"
    printf '@%s/.cursor/rules/%s-%s.mdc\n' "$project_dir" "$rule" "$slug"
}

renderizar_kickoff() {
    if [[ -z "$prompt_template" || ! -f "$prompt_template" ]]; then
        if [[ "${modo_oneshot:-0}" -eq 1 ]]; then
            print_error "no se encontró trio-os-prompt.md (definí PJ_TRIO_OS_PROMPT)." >&2
        else
            print_error "no se encontró trio-pm-prompt.md (definí PJ_TRIO_PM_PROMPT)." >&2
        fi
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
        wk_merge=" Es un sub-issue: con CI verde y code-review limpio, mergeá vos tu PR a ${base_rama} con gh pr merge <pr> -R ${pr_repo:-} --squash --delete-branch --match-head-commit <sha-verde> y anotá el sha del merge en wk.md."
        nota_subissue="Este ticket es un sub-issue (base ${base_rama}): no hay paso RV ni merge tuyo. El WK mergea su PR a la rama del spec (ADR 0018 de pj-template). Confirmá en GitHub que quedó mergeado (\`gh pr view <pr> -R ${pr_repo:-} --json state,mergeCommit\`) y saltá al paso 7. El PR final de la rama del spec lo revisa RV y lo mergeás vos."
    fi
    local wk_issue_ref="" os_issue_ref="Closes #${ticket}"
    if [[ "${issue_repo:-}" != "${pr_repo:-}" ]]; then
        wk_issue_ref=", referenciando ${issue_repo}#${ticket} en el body (no Closes #${ticket})"
        os_issue_ref="${issue_repo}#${ticket} (en vez de Closes #${ticket})"
    fi
    local wk_rule_prefix="" rv_rule_prefix=""
    if [[ "${WK_KIND:-}" == cursor ]]; then
        wk_rule_prefix="$(trio_cursor_rule_ref wk) "
    fi
    if [[ "${RV_KIND:-}" == cursor ]]; then
        rv_rule_prefix="$(trio_cursor_rule_ref rv) "
    fi
    local t
    t="$(cat "$prompt_template")"
    if [[ "${modo_spec:-0}" -eq 1 ]]; then
        local rama_spec="specs/${ticket}-<slug>"
        local spec_base_pr="${base_rama:-la rama por defecto}"
        local flujo_spec
        flujo_spec="1. Leé el spec y sus sub-issues vinculados (\`gh issue view {{TICKET}} -R {{ISSUE_REPO}} --comments\`) y escribí {{TRIO_DIR}}/plan.md con la rama del spec (${rama_spec}), el orden de sub-issues y sus criterios. Commit + push del meta-repo.
2. Asegurá la rama del spec (${rama_spec}) en origin saliendo de {{BASE_REF}} (sin trabajar en el clon {{MIEMBRO_DIR}}): los worktrees de cada sub-issue saldrán de \`origin/${rama_spec}\` bajo {{WT_RAIZ}} (bare en {{BARE_HOME}}).
3. Mandale el spec completo a WK vos mismo:
   \`herdr agent prompt {{AGENTE_WK}} \"{{WK_RULE_PREFIX}}Sos WK del spec {{ISSUE_REPO}}#{{TICKET}}. Leé {{TRIO_DIR}}/plan.md y ejecutá /implement-spec sobre el spec #{{TICKET}}: por cada sub-issue prepará el bare con {{WT_PREP}} y creá un worktree nuevo bajo {{WT_RAIZ}} sobre origin/${rama_spec} (con ravn-wt create -r {{WT_RAIZ}} -B 'origin/${rama_spec}' -b issue/<subticket>-<slug> -p '' issue/<subticket>-<slug>), implementá, corré /code-review y mergeá cada sub-PR a la rama del spec (${rama_spec}); al terminar todos los sub-issues, abrí el PR final de ${rama_spec} hacia ${spec_base_pr} con: gh pr create -R {{PR_REPO}}{{GH_PR_BASE}} (body con /pr referenciando {{ISSUE_REPO}}#{{TICKET}} y --draft según tus reglas), y escribí {{TRIO_DIR}}/wk.md con el PR final, head sha y pruebas.\"\`
   Esperá con \`herdr agent wait {{AGENTE_WK}} --timeout 600000\` y confirmá con \`herdr agent read {{AGENTE_WK}}\` y que exista wk.md (si devuelve \`idle\` sin wk.md, verificá actividad antes de contarlo como fallo). Si falla, aplicá la sección Fallos."
        local antes="${t%%1. Leé el ticket*}"
        local despues="4. (Trivial o PR final)${t#*4. (Trivial o PR final)}"
        t="${antes}${flujo_spec}"$'\n'"${despues}"
    fi
    t="${t//\{\{PROYECTO\}\}/$project_name}"
    t="${t//\{\{PROYECTO_DIR\}\}/$project_dir}"
    t="${t//\{\{TICKET\}\}/$ticket}"
    t="${t//\{\{ISSUE_REPO\}\}/${issue_repo:-}}"
    t="${t//\{\{PR_REPO\}\}/${pr_repo:-}}"
    t="${t//\{\{TICKET_REPO\}\}/${issue_repo:-}}"
    t="${t//\{\{WK_ISSUE_REF\}\}/"$wk_issue_ref"}"
    t="${t//\{\{OS_ISSUE_REF\}\}/"$os_issue_ref"}"
    t="${t//\{\{MIEMBRO_DIR\}\}/$miembro_dir}"
    t="${t//\{\{TRIO_DIR\}\}/$trio_dir}"
    t="${t//\{\{BASE_REF\}\}/"$base_ref"}"
    t="${t//\{\{BASE_PR\}\}/"$base_pr"}"
    t="${t//\{\{GH_PR_BASE\}\}/"$gh_pr_base"}"
    t="${t//\{\{WK_MERGE\}\}/"$wk_merge"}"
    t="${t//\{\{NOTA_SUBISSUE\}\}/"$nota_subissue"}"
    t="${t//\{\{WK_RULE_PREFIX\}\}/$wk_rule_prefix}"
    t="${t//\{\{RV_RULE_PREFIX\}\}/$rv_rule_prefix}"
    local wt_prep=""
    if [[ -n "${bare_dir:-}" && -d "${bare_dir}" ]]; then
        wt_prep="git -C ${bare_dir} fetch --prune origin && git -C ${bare_dir} remote set-head origin --auto"
    else
        wt_prep="ravn-wt clone ${miembro_slug:-}"
    fi
    t="${t//\{\{BARE_HOME\}\}/"${BARE_HOME}"}"
    t="${t//\{\{WORKTREES_HOME\}\}/"${WORKTREES_HOME}"}"
    t="${t//\{\{BARE_DIR\}\}/"${bare_dir:-}"}"
    t="${t//\{\{WT_PREP\}\}/"$wt_prep"}"
    t="${t//\{\{WT_RAIZ\}\}/"${wt_raiz:-}"}"
    t="${t//\{\{MIEMBRO_SLUG\}\}/"${miembro_slug:-}"}"
    t="${t//\{\{AGENTE_PM\}\}/$agent_pm}"
    t="${t//\{\{AGENTE_WK\}\}/$agent_wk}"
    t="${t//\{\{AGENTE_RV\}\}/$agent_rv}"
    t="${t//\{\{AGENTE_OS\}\}/${agent_os:-}}"
    t="${t//\{\{TRIO_STATUS\}\}/$trio_status}"
    t="${t//\{\{WORKSPACE_NOMBRE\}\}/${ws_label:-}}"
    printf '%s\n' "$t"
}
