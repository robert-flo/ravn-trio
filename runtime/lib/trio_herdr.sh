#!/usr/bin/env bash

# Operaciones sobre herdr, agy y git que usa el módulo start.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

# Identidad git: la fija pj-trio en la config local de cada repo (idempotente).
fijar_identidad_git() {
    if [[ -z "$TRIO_GIT_NAME" || -z "$TRIO_GIT_EMAIL" ]]; then
        print_warn "TRIO_GIT_NAME/TRIO_GIT_EMAIL vacíos en la config; no se fija identidad git." >&2
        return 0
    fi
    local dirs=("$project_dir")
    [[ -n "$repo_path" ]] && dirs+=("$repo_path")
    local d
    for d in "${dirs[@]}"; do
        git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || continue
        if [[ "$dry_run" -eq 1 ]]; then
            echo "[dry-run] git -C \"$d\" config user.name \"$TRIO_GIT_NAME\""
            echo "[dry-run] git -C \"$d\" config user.email \"$TRIO_GIT_EMAIL\""
            continue
        fi
        [[ "$(git -C "$d" config --local user.name || true)" == "$TRIO_GIT_NAME" ]] || git -C "$d" config user.name "$TRIO_GIT_NAME"
        [[ "$(git -C "$d" config --local user.email || true)" == "$TRIO_GIT_EMAIL" ]] || git -C "$d" config user.email "$TRIO_GIT_EMAIL"
    done
}

# Envío del arranque al PM: una sola vez por ticket (marcador status.json).
enviar_kickoff() {
    if [[ "$kickoff" -eq 0 || -z "$PM_KIND" ]]; then
        return 0
    fi
    if [[ "${pm_fallo_inicio:-0}" -eq 1 ]]; then
        return 0
    fi
    if [[ "${pm_duplicado:-0}" -eq 1 ]]; then
        print_warn "${agent_pm} ya corre en otro pane; no envío el arranque ni escribo status.json." >&2
        return 0
    fi
    if [[ "${kickoff_en_arranque:-0}" -eq 1 ]]; then
        # agy ya recibió el arranque con -i/--prompt-interactive al iniciar.
        echo "Arranque enviado a ${agent_pm} al iniciar agy (-i, sesión interactiva)."
        if [[ -f "${trio_dir}/status.json" ]]; then
            echo "status.json ya existía; se conserva (el PM retoma desde ahí)."
        elif [[ "$dry_run" -eq 1 ]]; then
            "$trio_status" --dry-run "$trio_dir" en-curso plan
        else
            "$trio_status" "$trio_dir" en-curso plan
        fi
        return 0
    fi
    if [[ -f "${trio_dir}/status.json" ]]; then
        echo "Arranque ya enviado (existe ${trio_dir}/status.json); no se reenvía."
        return 0
    fi
    local texto
    texto="$(renderizar_kickoff)" || return 1
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[dry-run] mkdir -p \"$trio_dir\""
        echo "[dry-run] herdr agent prompt \"$agent_pm\" \"<trio-pm-prompt.md renderizado>\""
        "$trio_status" --dry-run "$trio_dir" en-curso plan
        return 0
    fi
    if ! esperar_agente_listo "$agent_pm"; then
        print_warn "${agent_pm} no quedó listo a tiempo; no envío el arranque." >&2
        print_info "Pegalo a mano: pj-trio --print-kickoff ${project_name} ${ticket}${repo_arg:+ --repo $repo_arg}" >&2
        return 0
    fi
    local out
    if ! out="$(herdr agent prompt "$agent_pm" "$texto" 2>&1)"; then
        print_warn "no se pudo enviar el arranque a ${agent_pm}: ${out}" >&2
        print_info "Pegalo a mano: pj-trio --print-kickoff ${project_name} ${ticket}${repo_arg:+ --repo $repo_arg}" >&2
        return 0
    fi
    "$trio_status" "$trio_dir" en-curso plan
}

# 5. Verificación de agentes disponibles para agy
verificar_agentes_disponibles() {
    local necesita_agy=0
    for k in "$PM_KIND" "$WK_KIND" "$RV_KIND"; do
        if [[ "$k" == agy ]]; then
            necesita_agy=1
            break
        fi
    done

    if [[ "$necesita_agy" -eq 1 ]]; then
        if ! command -v agy >/dev/null 2>&1; then
            if [[ "$dry_run" -eq 1 ]]; then
                echo "[dry-run] Aviso: 'agy' no está en el PATH; se omite la verificación de agentes." >&2
                return 0
            fi
            print_error "el comando 'agy' no está disponible en el PATH." >&2
            exit 1
        fi
        local available_agents
        available_agents="$(agy agents 2>/dev/null || true)"
        for role in PM WK RV; do
            local k=""
            case "$role" in
                PM) k="$PM_KIND" ;;
                WK) k="$WK_KIND" ;;
                RV) k="$RV_KIND" ;;
            esac
            if [[ "$k" == agy ]]; then
                local expected="${role}-${project_name}"
                if ! echo "$available_agents" | grep -Fxq "$expected"; then
                    print_error "el agente '$expected' no está disponible en 'agy agents'." >&2
                    print_info "Asegurate de que el agente esté registrado en agy (ver 'agy agents')." >&2
                    [[ "$dry_run" -eq 1 ]] || exit 1
                fi
            fi
        done
    fi
}

# 6. Instalación idempotente de integraciones de herdr
instalar_integraciones() {
    local kinds=()
    for k in "$PM_KIND" "$WK_KIND" "$RV_KIND"; do
        [[ -z "$k" ]] && continue
        local target="$k"
        if [[ "$k" == agy && -n "${TRIO_HERDR_INTEGRATION_AGY:-}" ]]; then
            target="$TRIO_HERDR_INTEGRATION_AGY"
        fi
        local already=0
        for item in "${kinds[@]}"; do
            if [[ "$item" == "$target" ]]; then
                already=1
                break
            fi
        done
        if [[ "$already" -eq 0 ]]; then
            kinds+=("$target")
        fi
    done

    if [[ ${#kinds[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if command -v herdr >/dev/null 2>&1; then
            local status_out
            status_out="$(herdr integration status 2>/dev/null || true)"
            for target in "${kinds[@]}"; do
                if echo "$status_out" | grep -E "^${target}:" | grep -q "not installed"; then
                    echo "[dry-run] herdr integration install \"$target\""
                fi
            done
        fi
        return 0
    fi

    if ! command -v herdr >/dev/null 2>&1; then
        return 0
    fi

    local status_out
    status_out="$(herdr integration status 2>/dev/null || true)"
    for target in "${kinds[@]}"; do
        if echo "$status_out" | grep -E "^${target}:" | grep -q "not installed"; then
            echo "Instalando integración para $target..."
            if ! herdr integration install "$target"; then
                print_warn "no se pudo instalar la integración para $target" >&2
            fi
        fi
    done
}

# 11. Inicio de agentes por rol
iniciar_agente_rol() {
    local role="$1"
    local pane_id="$2"
    local kind="$3"

    if [[ -z "$kind" || -z "$pane_id" ]]; then
        # Kind vacío o sin panel: queda el shell interactivo para inicio manual
        return 0
    fi

    local agent_name
    agent_name="$(nombre_agente "$role")"

    local live_agents
    live_agents="$(herdr agent list 2>/dev/null || true)"
    if echo "$live_agents" | jq -e --arg p "$pane_id" \
        '.result.agents[]? | select(.pane_id == $p)' >/dev/null 2>&1; then
        return 0
    fi
    # El nombre es por proyecto: si ya vive en otro pane (otro ticket abierto), no se duplica.
    if echo "$live_agents" | jq -e --arg n "$agent_name" \
        '.result.agents[]? | select(.name == $n)' >/dev/null 2>&1; then
        print_warn "el agente '${agent_name}' ya corre en otro pane; ese ticket ya tiene su trío abierto." >&2
        [[ "$role" == "PM" ]] && pm_duplicado=1
        return 0
    fi

    local pane_info
    pane_info="$(herdr pane get "$pane_id" 2>/dev/null || true)"
    if echo "$pane_info" | jq -e '.result.pane.agent // empty | select(. != "")' >/dev/null 2>&1; then
        return 0
    fi

    local agent_args=(--agent "${role}-${project_name}")
    if [[ -n "$repo_path" ]]; then
        # El pane abre en el miembro; el meta-repo se añade al workspace de agy.
        agent_args+=(--add-dir "$project_dir")
    fi
    # agy 1.4.x: -i/--prompt-interactive envía el prompt inicial y sigue interactivo
    # (https://antigravity.google/docs/cli/reference/). Evita depender de herdr agent prompt.
    # herdr 0.9.5 rechaza argumentos con caracteres de control (saltos de línea)
    # (herdrdev/herdr src/app/agents.rs:159, error invalid_agent_argument): el
    # arranque va a un archivo y -i lleva solo una línea que apunta a él.
    local kickoff_pm=0
    # Un PM recién lanzado no tiene contexto: recibe siempre el arranque, aunque
    # exista status.json (p. ej. de un intento anterior en que el PM no arrancó).
    if [[ "$role" == PM && "$kind" == agy && "$kickoff" -eq 1 ]]; then
        if [[ -f "${trio_dir}/status.json" ]]; then
            echo "PM: existe ${trio_dir}/status.json, pero el PM es nuevo: le paso el arranque igual."
        fi
        local archivo_kickoff="${trio_dir}/kickoff.md"
        mkdir -p "$trio_dir"
        if renderizar_kickoff > "$archivo_kickoff"; then
            agent_args+=(-i "Lee y segui al pie de la letra las instrucciones de arranque del archivo ${archivo_kickoff}")
            kickoff_pm=1
            echo "PM: arranco agy con -i apuntando al arranque en ${archivo_kickoff} (ticket ${ticket})."
        fi
    fi

    local start_output
    if ! start_output="$(herdr agent start "$agent_name" --kind "$kind" --pane "$pane_id" -- "${agent_args[@]}" 2>&1)"; then
        # Si el agente requiere interacción o confirmación inicial (ej. prompts de bienvenida o permisos),
        # herdr reporta agent_not_ready. El proceso queda corriendo en el panel.
        # agent_not_ready y timeout (herdr src/cli/agent.rs:722-727, tras escribir ya el
        # comando en el pane) significan que agy se lanzó aunque herdr no lo confirmó.
        if echo "$start_output" | jq -e '.error.code == "agent_not_ready" or .error.code == "timeout"' >/dev/null 2>&1; then
            print_warn "${role}: herdr no confirmó el arranque a tiempo (diálogo de confianza?); agy ya quedó lanzado en ${pane_id}." >&2
            if [[ "$kickoff_pm" -eq 1 ]]; then kickoff_en_arranque=1; fi
        else
            if [[ "$role" == PM ]]; then pm_fallo_inicio=1; fi
            local err_msg
            err_msg="$(echo "$start_output" | jq -r '.error.message // empty' 2>/dev/null || true)"
            if [[ -n "$err_msg" ]]; then
                print_warn "no se pudo iniciar automáticamente el agente para ${role}: ${err_msg}" >&2
            else
                print_warn "no se pudo iniciar automáticamente el agente para ${role}: ${start_output}" >&2
            fi
            if [[ "$role" == PM ]]; then
                print_error "el PM no arrancó; no se envía el arranque ni se marca status.json." >&2
                print_info "Para recuperar, en el pane ${pane_id}: agy --agent ${role}-${project_name}${repo_path:+ --add-dir $project_dir} -i \"Lee y segui las instrucciones de arranque del archivo ${trio_dir}/kickoff.md\"" >&2
            fi
        fi
    else
        if [[ "$kickoff_pm" -eq 1 ]]; then kickoff_en_arranque=1; fi
    fi
}
