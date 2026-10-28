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

# Busca el proyecto meta por ruta o nombre en las raíces y el padre de $PWD;
# deja el resultado en project_dir (vacío si no está).
_trio_buscar_proyecto() {
    project_dir=""
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

}

# Clona UN repo (dueño/nombre) en <raíz> con PJ_TRIO_CLONE_CMD; en dry-run
# solo muestra el comando y falla.
_trio_clonar() {
    [[ "${PJ_TRIO_NO_CLONE:-0}" == 1 ]] && return 1
    local url="https://github.com/$1.git" cmd defecto='try exec --path {root} clone {url} | bash'
    cmd="${PJ_TRIO_CLONE_CMD:-$defecto}"
    cmd="${cmd//\{root\}/$(printf '%q' "$2")}"
    cmd="${cmd//\{url\}/$(printf '%q' "$url")}"
    if [[ "${dry_run:-0}" -eq 1 ]]; then
        print_info "(dry-run) se ejecutaría: $cmd" >&2
        return 1
    fi
    if ! bash -o pipefail -c "$cmd" >&2; then
        print_error "falló el clon de $1 ($cmd)" >&2
        return 1
    fi
}

# Clona con try-clone el meta-repo que falta (solo ése) y vuelve a resolver.
# PJ_TRIO_CLONE_CMD: {root} y {url}; default `try exec --path {root} clone {url} | bash`.
# PJ_TRIO_OWNER: dueño cuando se pasa solo el nombre (default robert-flo).
# PJ_TRIO_NO_CLONE=1 lo desactiva.
_trio_clonar_proyecto() {
    [[ "${PJ_TRIO_NO_CLONE:-0}" == 1 ]] && return 1
    local arg="$proyecto_arg" slug raiz
    [[ "$arg" == /* || "$arg" == .* || "$arg" == ~* ]] && return 1
    if [[ "$arg" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        slug="$arg"
    elif [[ "$arg" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        slug="${PJ_TRIO_OWNER:-robert-flo}/$arg"
    else
        return 1
    fi
    # dueño/nombre que ya está clonado con otro nombre de directorio.
    if [[ "$arg" == */* ]]; then
        proyecto_arg="${slug#*/}"
        _trio_buscar_proyecto
        [[ -n "$project_dir" ]] && return 0
        proyecto_arg="$arg"
    fi
    raiz="${raices[0]:-}"
    if [[ -z "$raiz" ]]; then
        # shellcheck disable=SC2086 # Lista separada por espacios a propósito.
        set -- ${PJ_TRIO_ROOT:-} ${PJ_TRIO_ROOTS:-/z-drive/tries}
        raiz="${1:-/z-drive/tries}"
    fi
    print_info "El proyecto '$proyecto_arg' no está clonado: clonando $slug en $raiz con try-clone…" >&2
    _trio_clonar "$slug" "$raiz" || return 1
    mapfile -t raices < <(trio_raices)
    [[ " ${raices[*]} " == *" $raiz "* ]] || raices=("$raiz" "${raices[@]}")
    proyecto_arg="${slug#*/}"
    _trio_buscar_proyecto
    [[ -n "$project_dir" ]]
}

trio_resolver_proyecto() {
    # 2. Resolución del directorio del proyecto meta: ruta, o nombre buscado en
    # $PJ_TRIO_ROOT(S) (default /z-drive/tries) y el padre de $PWD, también con
    # el prefijo de fecha de `try clone` (AAAA-MM-DD-<dueño>-<nombre>).
    project_dir=""
    local -a raices=()
    mapfile -t raices < <(trio_raices)
    while [[ "$proyecto_arg" == *[.,] ]]; do proyecto_arg="${proyecto_arg%[.,]}"; done
    _trio_buscar_proyecto
    [[ -n "$project_dir" ]] || _trio_clonar_proyecto || true

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
        # Puntuación final tipeada por error (`--repo foo.` o `foo,`).
        while [[ "$repo_arg" == *[.,] ]]; do repo_arg="${repo_arg%[.,]}"; done
        local buscado="${repo_arg##*/}" rc=0
        [[ "$repo_arg" == */* && -d "$repo_arg" ]] && buscado="$repo_arg"
        repo_path="$(trio_buscar_repo "$buscado" "$project_dir" "$(dirname "$project_dir")" "${raices[@]}")" || rc=$?
        if ((rc == 2)); then
            print_error "el repositorio miembro '$repo_arg' es ambiguo (candidatos arriba); pasá el nombre completo o la ruta." >&2
            exit 1
        elif ((rc != 0)) || [[ -z "$repo_path" ]]; then
            local mslug="$repo_arg"
            [[ "$mslug" == */* ]] || mslug="${project_slug%%/*}"/"$repo_arg"
            [[ "$mslug" == /* ]] && mslug="${PJ_TRIO_OWNER:-robert-flo}/$repo_arg"
            if command -v gh >/dev/null 2>&1 && [[ "$repo_arg" != /* ]]; then
                local gh_err gh_rc=0
                gh_err="$(gh repo view "$mslug" --json name 2>&1 >/dev/null)" || gh_rc=$?
                if ((gh_rc != 0)) && ! grep -qiE 'could not resolve to a repository|not found|404' <<<"$gh_err"; then
                    print_error "no pude consultar GitHub por $mslug (¿sin red o gh sin sesión?): ${gh_err%%$'\n'*}" >&2
                elif ((gh_rc == 0)); then
                    print_info "$mslug existe en GitHub pero no está clonado: clonándolo en $project_dir con try-clone…" >&2
                    if _trio_clonar "$mslug" "$project_dir"; then
                        repo_path="$(trio_buscar_repo "${mslug#*/}" "$project_dir" "$(dirname "$project_dir")" "${raices[@]}")" || repo_path=""
                    fi
                else
                    print_error "el repositorio $mslug no existe en GitHub (o no tenés acceso): revisá el nombre." >&2
                fi
            fi
            if [[ -z "$repo_path" ]]; then
                print_error "no se encontró el repositorio miembro '$repo_arg'" >&2
                print_info "Pista: pasá la ruta, el nombre del repo en GitHub o cloná el miembro (try clone) en ${raices[*]:-/z-drive/tries}." >&2
                exit 1
            fi
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

# 4b. Nombres de agente: <rol>-<miembro corto>-<ticket>. herdr exige
# ^[a-z][a-z0-9_-]{0,31}$, así que se sanea, se quitan prefijos comunes
# (pj-domina-, rf-, fo-) y, si aún no cabe, se trunca y se agrega un hash de
# 4 caracteres del nombre completo. Determinista: mismo trío → mismo nombre.
sanear_nombre() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n-' '-'
}

nombre_agente() {
    local rol base t nombre max hash
    rol="$(sanear_nombre "$1")"
    base="$(sanear_nombre "${repo_name:-$project_name}")"
    local prev=""
    while [[ "$base" != "$prev" ]]; do
        prev="$base"
        base="${base#pj-domina-}"; base="${base#rf-}"; base="${base#fo-}"
    done
    [[ -n "$base" ]] || base="$(sanear_nombre "$project_name")"
    t="$(sanear_nombre "$ticket")"
    nombre="${rol}-${base}-${t}"
    if (( ${#nombre} > 32 )); then
        hash="$(printf '%s' "${project_name}/${repo_name}#${ticket}" | sha1sum | cut -c1-4)"
        max=$(( 32 - ${#rol} - ${#t} - 7 ))   # 3 guiones + 4 de hash
        if (( max < 1 )); then
            nombre="${rol:0:22}-${hash}-${t:0:4}"
            nombre="${nombre:0:32}"
        else
            base="${base:0:max}"; base="${base%-}"
            nombre="${rol}-${base}-${hash}-${t}"
        fi
    fi
    echo "$nombre"
}
