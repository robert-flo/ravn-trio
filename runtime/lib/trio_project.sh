#!/usr/bin/env bash

# Resolución del proyecto meta, del repo miembro y de los nombres de agente.
# shellcheck disable=SC2034,SC2154 # Globals are shared by runtime/scripts/start before these functions run.

# Raíces de clones donde se buscan proyecto y miembros (try-clone / try clone).
# PJ_TRIO_ROOTS: lista separada por espacios; PJ_TRIO_ROOT se sigue aceptando.
trio_raices() {
    local r
    # shellcheck disable=SC2086 # Lista separada por espacios a propósito.
    for r in ${PJ_TRIO_ROOT:-} ${PJ_TRIO_ROOTS:-/z-drive/tries}; do
        [[ -d "$r" ]] && printf '%s\n' "$r"
    done
}

# owner/nombre del remoto origin de GitHub (vacío si no es de GitHub).
trio_slug_remoto() {
    local url
    url="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
    url="${url%.git}"
    url="${url%/}"
    if [[ "$url" =~ github\.com[:/]+([^/]+/[^/]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

# Nombre canónico de un repo local: el del remoto origin; si no hay, el
# directorio sin el prefijo de try (AAAA-MM-DD-<dueño>-) ni rf-/fo-.
trio_nombre_repo() {
    local slug base
    slug="$(trio_slug_remoto "$1")"
    if [[ -n "$slug" ]]; then
        printf '%s\n' "${slug#*/}"
        return
    fi
    base="$(basename "$1")"
    printf '%s\n' "$base"
}

# Nombre del proyecto: `proyecto:` de proyecto.yml, si no el del remoto.
trio_nombre_proyecto() {
    local p=""
    if [[ -f "$1/proyecto.yml" ]]; then
        p="$(sed -nE 's/^proyecto:[[:space:]]*"?([^"#[:space:]]+)"?.*/\1/p' "$1/proyecto.yml" | head -n1)"
    fi
    [[ -n "$p" ]] || p="$(trio_nombre_repo "$1")"
    printf '%s\n' "$p"
}

# Repos miembros declarados en proyecto.yml (repos: - repo: "dueño/nombre").
trio_miembros_declarados() {
    [[ -f "$1/proyecto.yml" ]] || return 0
    awk '/^repos:/{f=1;next} /^[^[:space:]#-]/{f=0} f && /repo:/{gsub(/["\047]/,"",$0); sub(/.*repo:[[:space:]]*/,""); sub(/[[:space:]#].*/,""); print}' "$1/proyecto.yml"
}

# Directorios git candidatos (profundidad 1 y 2) bajo las bases dadas.
trio_dirs_git() {
    local base d
    for base in "$@"; do
        [[ -d "$base" ]] || continue
        for d in "$base" "$base"/*/ "$base"/*/*/; do
            d="${d%/}"
            [[ -e "$d/.git" ]] && printf '%s\n' "$d"
        done
    done | awk '!seen[$0]++'
}

# Busca un repo por nombre: ruta, nombre de directorio exacto, nombre del
# remoto, y por último nombre corto (sufijo -<nombre>) si es único.
# Imprime la ruta absoluta; retorno 1 si no hay, 2 si es ambiguo.
trio_buscar_repo() {
    local arg="$1" d
    shift
    if [[ -d "$arg" ]]; then
        (cd "$arg" && pwd)
        return 0
    fi
    local -a dirs=() exactos=() sufijo=()
    mapfile -t dirs < <(trio_dirs_git "$@")
    for d in "${dirs[@]}"; do
        local base nombre
        base="$(basename "$d")"
        nombre="$(trio_nombre_repo "$d")"
        if [[ "$base" == "$arg" || "$nombre" == "$arg" || "$base" == "rf-$arg" || "$base" == "fo-$arg" || "$base" == *-"$arg" && "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
            exactos+=("$d")
        elif [[ "$nombre" == *-"$arg" ]]; then
            sufijo+=("$d")
        fi
    done
    if ((${#exactos[@]})); then
        (cd "${exactos[0]}" && pwd)
        return 0
    fi
    # Varios clones del mismo remoto cuentan como uno (gana el primero).
    local -A vistos=()
    local -a unicos=()
    for d in "${sufijo[@]}"; do
        local n
        n="$(trio_nombre_repo "$d")"
        [[ -n "${vistos[$n]:-}" ]] && continue
        vistos[$n]=1
        unicos+=("$d")
    done
    if ((${#unicos[@]} == 1)); then
        (cd "${unicos[0]}" && pwd)
        return 0
    fi
    if ((${#unicos[@]} > 1)); then
        for d in "${unicos[@]}"; do printf '%s\n' "$d" >&2; done
        return 2
    fi
    return 1
}

trio_resolver_proyecto() {
    # 2. Resolución del directorio del proyecto meta: ruta, o nombre buscado en
    # $PJ_TRIO_ROOT(S) (default /z-drive/tries) y el padre de $PWD, también con
    # el prefijo de fecha de `try clone` (AAAA-MM-DD-<dueño>-<nombre>).
    project_dir=""
    local -a raices=()
    mapfile -t raices < <(trio_raices)
    if [[ -d "$proyecto_arg" ]]; then
        project_dir="$(cd "$proyecto_arg" && pwd)"
    else
        local c
        for c in "${raices[@]}" "$(dirname "$PWD")"; do
            if [[ -d "${c}/${proyecto_arg}" ]]; then
                project_dir="$(cd "${c}/${proyecto_arg}" && pwd)"
                break
            fi
        done
        if [[ -z "$project_dir" ]]; then
            local d
            for c in "${raices[@]}" "$(dirname "$PWD")"; do
                for d in "$c"/*/; do
                    d="${d%/}"
                    [[ -e "$d/.git" ]] || continue
                    if [[ "$(trio_nombre_repo "$d")" == "$proyecto_arg" ]]; then
                        project_dir="$d"
                        break 2
                    fi
                done
            done
        fi
    fi

    if [[ -z "$project_dir" ]]; then
        print_error "no se encontró el directorio del proyecto '$proyecto_arg'" >&2
        print_info "Pista: pasá una ruta existente, cloná el meta-repo (try clone) o configurá \$PJ_TRIO_ROOTS (default /z-drive/tries)." >&2
        exit 1
    fi

    project_name="$(trio_nombre_proyecto "$project_dir")"
    project_slug="$(trio_slug_remoto "$project_dir")"

    # 3. Resolución del repositorio miembro opcional (--repo). Mismo orden
    # siempre, sin depender de $PWD salvo para rutas: subdirectorios del
    # proyecto, hermanos, raíces; acepta nombre de directorio, nombre del
    # remoto (dueño/nombre también) o nombre corto (rf-git-setup →
    # pj-domina-rf-git-setup) si es único.
    repo_path=""
    repo_name=""
    repo_slug=""
    if [[ -n "$repo_arg" ]]; then
        local buscado="${repo_arg##*/}" rc=0
        [[ "$repo_arg" == */* && -d "$repo_arg" ]] && buscado="$repo_arg"
        repo_path="$(trio_buscar_repo "$buscado" "$project_dir" "$(dirname "$project_dir")" "${raices[@]}")" || rc=$?
        if ((rc == 2)); then
            print_error "el repositorio miembro '$repo_arg' es ambiguo (candidatos arriba); pasá el nombre completo o la ruta." >&2
            exit 1
        elif ((rc != 0)) || [[ -z "$repo_path" ]]; then
            print_error "no se encontró el repositorio miembro '$repo_arg'" >&2
            print_info "Pista: pasá la ruta, el nombre del repo en GitHub o cloná el miembro (try clone) en ${raices[*]:-/z-drive/tries}." >&2
            exit 1
        fi
        repo_name="$(trio_nombre_repo "$repo_path")"
        repo_slug="$(trio_slug_remoto "$repo_path")"
        if [[ "$repo_path" == "$project_dir" ]]; then
            repo_path=""
            repo_name=""
            repo_slug=""
        fi
    fi

    # Repo de GitHub donde vive el issue: el miembro si hay --repo, si no el meta.
    ticket_repo="${repo_slug:-${project_slug:-${repo_name:-$project_name}}}"

    if [[ -n "$repo_name" ]]; then
        ws_label="trio ${project_name}/${repo_name}#${ticket}"
    else
        ws_label="trio ${project_name}#${ticket}"
    fi
}

trio_nombres() {
    # Clave del trío: el número solo choca entre miembros (#4 de dos repos), así
    # que con --repo es <miembro>-<ticket>. Si ya existe el handoff viejo
    # (.trio/<ticket>) de un trío en curso, se respeta.
    ticket_key="$ticket"
    if [[ -n "$repo_name" && ! -d "${project_dir}/.trio/${ticket}" ]]; then
        ticket_key="${repo_name}-${ticket}"
    fi

    agent_pm="$(nombre_agente pm)"
    agent_wk="$(nombre_agente wk)"
    agent_rv="$(nombre_agente rv)"

    trio_dir="${project_dir}/.trio/${ticket_key}"
    miembro_dir="${repo_path:-$project_dir}"
}

# 4b. Nombres de agente por proyecto y ticket (permite varios tríos por proyecto)
nombre_agente() {
    local t
    t="$(echo "${ticket_key:-$ticket}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"
    echo "${1}-${project_name}-${t}" | tr '[:upper:]' '[:lower:]'
}
