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
    # La raíz de worktrees de ravn-git-bare-clone (si ya existe): sus worktrees heredan del bare.
    [[ -n "${wt_raiz:-}" && -e "${wt_raiz}/.git" ]] && dirs+=("$wt_raiz")
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

# _kickoff_aceptado <target>: 0 si el agente salió de idle o muestra actividad.
_kickoff_aceptado() {
    local target="$1" agent_json estado pantalla
    agent_json="$(herdr agent get "$target" 2>/dev/null || true)"
    estado="$(jq -r '.result.agent.agent_status // .result.agent.status // .result.status // empty' <<<"$agent_json" 2>/dev/null || true)"
    if [[ -n "$estado" && "$estado" != "idle" ]]; then
        return 0
    fi
    pantalla="$(herdr agent read "$target" 2>/dev/null | tail -n 30 || true)"
    if grep -qiE 'Generating\.\.\.' <<<"$pantalla"; then
        return 0
    fi
    return 1
}

# Envío del arranque al PM o al OS: una sola vez por ticket (marcador status.json).
enviar_kickoff() {
    local target_rol="pm" target_kind="$PM_KIND" target_agent="$agent_pm" target_pane="${pm_pane:-}"
    if [[ "${modo_oneshot:-0}" -eq 1 ]]; then
        target_rol="os"
        target_kind="$OS_KIND"
        target_agent="$agent_os"
        target_pane="${os_pane:-}"
    fi
    if [[ "$kickoff" -eq 0 || -z "$target_kind" ]]; then
        return 0
    fi
    if [[ "${pm_fallo_inicio:-0}" -eq 1 ]]; then
        return 0
    fi
    if [[ "${pm_duplicado:-0}" -eq 1 ]]; then
        print_warn "${target_agent} ya corre en otro pane; no envío el arranque ni escribo status.json." >&2
        return 0
    fi
    if [[ "${kickoff_en_arranque:-0}" -eq 1 ]]; then
        # cursor ya recibió el arranque al iniciar.
        echo "Arranque enviado a ${target_agent} al iniciar ${target_kind} (sesión interactiva)."
        if [[ -f "${trio_dir}/status.json" ]]; then
            echo "status.json ya existía; se conserva (el agente retoma desde ahí)."
        elif [[ "$dry_run" -eq 1 ]]; then
            "$trio_status" --dry-run "$trio_dir" en-curso plan
        else
            "$trio_status" "$trio_dir" en-curso plan
        fi
        return 0
    fi
    if [[ -f "${trio_dir}/status.json" && "${pm_recien_lanzado:-0}" -eq 0 ]]; then
        echo "Arranque ya enviado (existe ${trio_dir}/status.json); no se reenvía."
        return 0
    fi
    local kickoff_file="${pm_kickoff_file:-${trio_dir}/kickoff.md}"
    local texto="Lee y segui al pie de la letra las instrucciones de arranque del archivo ${kickoff_file}"
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[dry-run] mkdir -p \"$trio_dir\""
        echo "[dry-run] herdr agent prompt \"$target_agent\" \"$texto\""
        "$trio_status" --dry-run "$trio_dir" en-curso plan
        return 0
    fi
    if [[ ! -f "$kickoff_file" ]]; then
        mkdir -p "$trio_dir"
        renderizar_kickoff > "$kickoff_file" || return 1
    fi
    if [[ "${pm_start_confirmed:-0}" -eq 0 ]] && ! esperar_agente_listo "$target_agent" "$target_pane"; then
        print_warn "${target_agent} no quedó listo a tiempo; no envío el arranque." >&2
        print_info "Pegalo a mano: pj-trio --print-kickoff ${project_name} ${ticket}${repo_arg:+ --repo $repo_arg}${ticket_repo_arg:+ --ticket-repo $ticket_repo_arg}" >&2
        return 0
    fi
    local prompt_target="$target_agent"
    if [[ -n "$target_pane" ]] && ! herdr agent get "$target_agent" >/dev/null 2>&1; then
        prompt_target="$target_pane"
    fi
    local max_reintentos="${TRIO_KICKOFF_RETRIES:-2}"
    local verify_secs="${TRIO_KICKOFF_VERIFY_SECS:-2}"
    local intento=1 max_intentos=$(( max_reintentos + 1 )) kickoff_ok=0 out
    while (( intento <= max_intentos )); do
        if ! out="$(herdr agent prompt "$prompt_target" "$texto" 2>&1)"; then
            print_warn "no se pudo enviar el arranque a ${target_agent}: ${out}" >&2
            print_info "Pegalo a mano: pj-trio --print-kickoff ${project_name} ${ticket}${repo_arg:+ --repo $repo_arg}${ticket_repo_arg:+ --ticket-repo $ticket_repo_arg}" >&2
            return 0
        fi
        if [[ "$verify_secs" != "0" ]]; then
            sleep "$verify_secs"
        fi
        if _kickoff_aceptado "$prompt_target"; then
            kickoff_ok=1
            break
        fi
        if (( intento < max_intentos )); then
            print_warn "${target_agent} siguió idle tras el arranque (intento ${intento}/${max_intentos}); limpio la línea (Ctrl+U) y reintento..." >&2
            herdr agent send-keys "$prompt_target" ctrl+u >/dev/null 2>&1 || true
        fi
        intento=$(( intento + 1 ))
    done
    if [[ "$kickoff_ok" -eq 0 ]]; then
        local err_kickoff="kickoff no procesado por ${target_agent} tras ${max_reintentos} reintentos (sigue idle con texto en prompt)"
        print_warn "${err_kickoff}; marco status.json como blocked." >&2
        print_info "Pegalo a mano: pj-trio --print-kickoff ${project_name} ${ticket}${repo_arg:+ --repo $repo_arg}${ticket_repo_arg:+ --ticket-repo $ticket_repo_arg}" >&2
        "$trio_status" "$trio_dir" blocked plan --cola-de "$prompt_target" --error "$err_kickoff"
        return 0
    fi
    if [[ -f "${trio_dir}/status.json" ]]; then
        echo "status.json ya existía; se conserva (el agente retoma desde ahí)."
    else
        "$trio_status" "$trio_dir" en-curso plan
    fi
}

# 5. Verificación de agentes disponibles para agy y cursor
verificar_agentes_disponibles() {
    local roles=(PM WK RV)
    if [[ "${modo_oneshot:-0}" -eq 1 ]]; then
        roles=(OS)
    fi
    local necesita_agy=0 necesita_cursor=0
    for role in "${roles[@]}"; do
        local k=""
        case "$role" in
            PM) k="$PM_KIND" ;;
            WK) k="$WK_KIND" ;;
            RV) k="$RV_KIND" ;;
            OS) k="$OS_KIND" ;;
        esac
        case "$k" in
            agy) necesita_agy=1 ;;
            cursor) necesita_cursor=1 ;;
        esac
    done

    if [[ "$necesita_agy" -eq 1 ]]; then
        if ! command -v agy >/dev/null 2>&1; then
            if [[ "$dry_run" -eq 1 ]]; then
                echo "[dry-run] Aviso: 'agy' no está en el PATH; se omite la verificación de agentes." >&2
            else
                print_error "el comando 'agy' no está disponible en el PATH." >&2
                exit 1
            fi
        else
            local available_agents
            available_agents="$(agy agents 2>/dev/null || true)"
            for role in "${roles[@]}"; do
                local k=""
                case "$role" in
                    PM) k="$PM_KIND" ;;
                    WK) k="$WK_KIND" ;;
                    RV) k="$RV_KIND" ;;
                    OS) k="$OS_KIND" ;;
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
    fi

    if [[ "$necesita_cursor" -eq 1 ]]; then
        if ! command -v cursor-agent >/dev/null 2>&1 \
            && ! { command -v mise >/dev/null 2>&1 && mise x cursor-agent -- true >/dev/null 2>&1; }; then
            if [[ "$dry_run" -eq 1 ]]; then
                echo "[dry-run] Aviso: 'cursor-agent' no está disponible (ni en PATH ni vía mise); se omite la verificación." >&2
            else
                print_error "el comando 'cursor-agent' no está disponible en el PATH ni vía 'mise x cursor-agent'." >&2
                exit 1
            fi
        fi
    fi
}

# 6. Instalación idempotente de integraciones de herdr
instalar_integraciones() {
    local kinds=()
    local roles=(PM WK RV)
    if [[ "${modo_oneshot:-0}" -eq 1 ]]; then
        roles=(OS)
    fi
    for role in "${roles[@]}"; do
        local k=""
        case "$role" in
            PM) k="$PM_KIND" ;;
            WK) k="$WK_KIND" ;;
            RV) k="$RV_KIND" ;;
            OS) k="$OS_KIND" ;;
        esac
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

# Construye trio_agent_args=() y trio_kickoff_inline=0|1 para <role> <kind> <kickoff_file>.
trio_construir_args_agente() {
    local role="$1" kind="$2" kickoff_file="${3:-}"
    trio_agent_args=()
    trio_kickoff_inline=0

    if [[ "$kind" == cursor ]]; then
        trio_agent_args=(--yolo --trust --workspace "${work_dir:-$miembro_dir}" --add-dir "$project_dir")
        if [[ ("$role" == PM || "$role" == OS) && "$kickoff" -eq 1 && -n "$kickoff_file" ]]; then
            local rule_name="pm-trio"
            [[ "$role" == OS ]] && rule_name="os"
            trio_agent_args+=("$(trio_cursor_rule_ref "$rule_name") Lee y segui al pie de la letra las instrucciones de arranque del archivo ${kickoff_file}")
            trio_kickoff_inline=1
        fi
        return 0
    fi

    trio_agent_args=(--agent "${role}-${project_name}")
    if [[ -n "$repo_path" ]]; then
        # El pane abre en el miembro; el meta-repo se añade al workspace de agy.
        trio_agent_args+=(--add-dir "$project_dir")
    fi
    # Para agy se arranca sin -i para que herdr detecte interactive_ready=true
    # y registre el `name` del agente; luego enviar_kickoff manda el arranque
    # de una línea vía `herdr agent prompt` apuntando a kickoff.md.
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
        [[ "$role" == "PM" || "$role" == "OS" ]] && pm_duplicado=1
        return 0
    fi

    local pane_info
    pane_info="$(herdr pane get "$pane_id" 2>/dev/null || true)"
    if echo "$pane_info" | jq -e '.result.pane.agent // empty | select(. != "")' >/dev/null 2>&1; then
        return 0
    fi

    local archivo_kickoff="" kickoff_target=0
    # Un PM o OS recién lanzado no tiene contexto: recibe siempre el arranque, aunque
    # exista status.json (p. ej. de un intento anterior en que no arrancó).
    if [[ ("$role" == PM || "$role" == OS) && ("$kind" == agy || "$kind" == cursor) && "$kickoff" -eq 1 ]]; then
        if [[ -f "${trio_dir}/status.json" ]]; then
            echo "${role}: existe ${trio_dir}/status.json, pero el ${role} es nuevo: le paso el arranque igual."
        fi
        archivo_kickoff="${trio_dir}/kickoff.md"
        mkdir -p "$trio_dir"
        if renderizar_kickoff > "$archivo_kickoff"; then
            echo "${role}: arranco ${kind} apuntando al arranque en ${archivo_kickoff} (ticket ${ticket})."
            pm_kickoff_file="$archivo_kickoff"
        else
            archivo_kickoff=""
        fi
    fi

    [[ "$role" == PM || "$role" == OS ]] && pm_recien_lanzado=1

    trio_construir_args_agente "$role" "$kind" "$archivo_kickoff"
    kickoff_target="$trio_kickoff_inline"

    # Margen breve para que el shell del pane recién creado termine de tomar el PTY.
    if [[ "${TRIO_PANE_SETTLE_SECS:-0.3}" != "0" ]]; then
        sleep "${TRIO_PANE_SETTLE_SECS:-0.3}"
    fi

    local start_output="" start_ok=0 intento
    for intento in 1 2; do
        if start_output="$(herdr agent start "$agent_name" --kind "$kind" --pane "$pane_id" -- "${trio_agent_args[@]}" 2>&1)"; then
            start_ok=1
            break
        fi
        if [[ "$intento" -eq 1 ]] && echo "$start_output" | grep -qi "no longer owns the target terminal"; then
            sleep "${TRIO_START_RETRY_SECS:-1}"
            continue
        fi
        break
    done

    if [[ "$start_ok" -eq 0 ]]; then
        # Si el agente requiere interacción o confirmación inicial (ej. prompts de bienvenida o permisos),
        # herdr reporta agent_not_ready. El proceso queda corriendo en el panel.
        # agent_not_ready y timeout (herdr src/cli/agent.rs:722-727, tras escribir ya el
        # comando en el pane) significan que el agente se lanzó aunque herdr no lo confirmó.
        if echo "$start_output" | jq -e '.error.code == "agent_not_ready" or .error.code == "timeout"' >/dev/null 2>&1; then
            print_warn "${role}: herdr no confirmó el arranque a tiempo (diálogo de confianza?); ${kind} ya quedó lanzado en ${pane_id}." >&2
            if [[ "$kickoff_target" -eq 1 ]]; then kickoff_en_arranque=1; fi
        else
            if [[ "$role" == PM || "$role" == OS ]]; then pm_fallo_inicio=1; fi
            local err_msg pane_tail
            err_msg="$(echo "$start_output" | jq -r '.error.message // empty' 2>/dev/null || true)"
            if [[ -n "$err_msg" ]]; then
                print_warn "no se pudo iniciar automáticamente el agente para ${role}: ${err_msg}" >&2
            else
                print_warn "no se pudo iniciar automáticamente el agente para ${role}: ${start_output}" >&2
            fi
            pane_tail="$(herdr pane read "$pane_id" 2>/dev/null | tail -n 20 || true)"
            if [[ -n "$pane_tail" ]]; then
                print_warn "Última salida del pane ${pane_id}:"$'\n'"${pane_tail}" >&2
            fi
            if [[ "$role" == PM || "$role" == OS ]]; then
                print_error "el ${role} no arrancó; no se envía el arranque ni se marca status.json." >&2
                if [[ "$kind" == cursor ]]; then
                    print_info "Para recuperar, en el pane ${pane_id}: cursor-agent ${trio_agent_args[*]}" >&2
                else
                    print_info "Para recuperar, en el pane ${pane_id}: agy --agent ${role}-${project_name}${repo_path:+ --add-dir $project_dir} -i \"Lee y segui las instrucciones de arranque del archivo ${trio_dir}/kickoff.md\"" >&2
                fi
            fi
        fi
    else
        [[ "$role" == PM || "$role" == OS ]] && pm_start_confirmed=1
        if [[ "$kickoff_target" -eq 1 ]]; then kickoff_en_arranque=1; fi
    fi
}
