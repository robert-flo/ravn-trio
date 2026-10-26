#!/usr/bin/env bash

# Resolución del proyecto meta, del repo miembro y de los nombres de agente.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

trio_resolver_proyecto() {
    # 2. Resolución del directorio del proyecto meta
    project_dir=""
    if [[ -d "$proyecto_arg" ]]; then
        project_dir="$(cd "$proyecto_arg" && pwd)"
    else
        candidates=()
        if [[ -n "${PJ_TRIO_ROOT:-}" ]]; then
            candidates+=("${PJ_TRIO_ROOT}")
        fi
        candidates+=("$(dirname "$PWD")" "${HOME}/.cache/ravn-piloto")
        for c in "${candidates[@]}"; do
            if [[ -d "${c}/${proyecto_arg}" ]]; then
                project_dir="$(cd "${c}/${proyecto_arg}" && pwd)"
                break
            fi
        done
    fi

    if [[ -z "$project_dir" ]]; then
        print_error "no se encontró el directorio del proyecto '$proyecto_arg'" >&2
        print_info "Pista: podés pasar una ruta existente o configurar \$PJ_TRIO_ROOT (por defecto busca en el directorio padre de \$PWD o ~/.cache/ravn-piloto)." >&2
        exit 1
    fi

    project_name="$(basename "$project_dir")"

    # 3. Resolución del repositorio miembro opcional (--repo)
    repo_path=""
    repo_name=""
    if [[ -n "$repo_arg" ]]; then
        if [[ -d "$repo_arg" ]]; then
            repo_path="$(cd "$repo_arg" && pwd)"
        elif [[ -d "$(dirname "$project_dir")/$repo_arg" ]]; then
            repo_path="$(cd "$(dirname "$project_dir")/$repo_arg" && pwd)"
        elif [[ -d "${project_dir}/$repo_arg" ]]; then
            repo_path="$(cd "${project_dir}/$repo_arg" && pwd)"
        elif [[ -n "${PJ_TRIO_ROOT:-}" && -d "${PJ_TRIO_ROOT}/$repo_arg" ]]; then
            repo_path="$(cd "${PJ_TRIO_ROOT}/$repo_arg" && pwd)"
        else
            print_error "no se encontró el repositorio miembro '$repo_arg'" >&2
            print_info "Pista: el repositorio miembro debe existir como ruta o hermano/subdirectorio del proyecto." >&2
            exit 1
        fi
        repo_name="$(basename "$repo_path")"
    fi

    if [[ -n "$repo_name" ]]; then
        ws_label="trio ${project_name}/${repo_name}#${ticket}"
    else
        ws_label="trio ${project_name}#${ticket}"
    fi
}

trio_nombres() {
    agent_pm="$(nombre_agente pm)"
    agent_wk="$(nombre_agente wk)"
    agent_rv="$(nombre_agente rv)"

    trio_dir="${project_dir}/.trio/${ticket}"
    miembro_dir="${repo_path:-$project_dir}"
}

# 4b. Nombres de agente por proyecto y ticket (permite varios tríos por proyecto)
nombre_agente() {
    local t
    t="$(echo "$ticket" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"
    echo "${1}-${project_name}-${t}" | tr '[:upper:]' '[:lower:]'
}
