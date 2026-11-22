#!/usr/bin/env bash

if [[ ${_PJ_TRIO_BASH_COMPLETION_LOADED:-0} == 1 ]]; then
  return 0
fi
readonly _PJ_TRIO_BASH_COMPLETION_LOADED=1

PJ_TRIO_COMPLETION_DIR=""
PJ_TRIO_COMPLETION_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly PJ_TRIO_COMPLETION_DIR
# shellcheck disable=SC1091
source "$PJ_TRIO_COMPLETION_DIR/../lib/command_catalog.sh"

# command_catalog_get parte cada fila con IFS=$'\t'. El tab es espacio en blanco
# de IFS, así que un icono vacío (dos tabs seguidos) colapsa y el campo options
# queda vacío. Acá se conserva cada campo, vacío o no.
_pj_trio_row_field() {
  local lookup="$1"
  local index="$2"
  local record="" rest="" field="" canonical="" aliases=""
  local -a fields=()

  for record in "${GIT_SETUP_COMMAND_CATALOG[@]}"; do
    fields=()
    rest="$record"
    while [[ "$rest" == *$'\t'* ]]; do
      field="${rest%%$'\t'*}"
      rest="${rest#*$'\t'}"
      fields+=("$field")
    done
    fields+=("$rest")
    canonical="${fields[0]:-}"
    aliases="${fields[1]:-}"
    if [[ "$canonical" == "$lookup" || " $aliases " == *" $lookup "* ]]; then
      printf '%s' "${fields[$index]:-}"
      return 0
    fi
  done
  return 1
}

# Nombres de Home Repo (HR-* / pj-*, o directorio con `proyecto:`) bajo las raíces.
_pj_trio_completar_homes() {
  local r d base
  # shellcheck disable=SC2086 # Lista separada por espacios a propósito.
  for r in ${PJ_TRIO_ROOT:-} ${PJ_TRIO_ROOTS:-/z-drive/tries /z-home-repos /z/repos}; do
    [[ -d "$r" ]] || continue
    for d in "$r"/*/; do
      [[ -d "$d" ]] || continue
      base="$(basename "$d")"
      if [[ "$base" == HR-* || "$base" == pj-* ]]; then
        printf '%s\n' "$base"
      elif [[ -f "${d%/}/proyecto.yml" ]] && grep -qE '^proyecto:[[:space:]]*"?[^"#[:space:]]+' "${d%/}/proyecto.yml"; then
        printf '%s\n' "$base"
      fi
    done
  done
}

_pj_trio_es_flota() {
  case "$1" in
    fleet|fl|--fleet|watch|w|--watch) return 0 ;;
    *) return 1 ;;
  esac
}

_pj_trio_completion() {
  local current="${COMP_WORDS[COMP_CWORD]}"
  local previous="${COMP_WORDS[COMP_CWORD - 1]:-}"
  local commands=""
  local options=""
  local cmd="${COMP_WORDS[1]:-}"
  local homes=""

  if ((COMP_CWORD == 1)); then
    commands=$(command_catalog_completion_words)
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$commands" -- "$current"))
    return 0
  fi

  # fleet/watch: <proyecto> es opcional. Flags solas si el token empieza por -,
  # y nombres de Home Repo junto a las flags en el hueco posicional.
  if _pj_trio_es_flota "$cmd"; then
    case "$previous" in
      --ticket|--snapshot|--timeout) return 0 ;;
    esac
    options="$(_pj_trio_row_field "$cmd" 6 || true)"
    if [[ "$current" == -* ]]; then
      # shellcheck disable=SC2207 # Bash completion requires word splitting here.
      COMPREPLY=($( compgen -W "$options" -- "$current"))
      return 0
    fi
    homes="$(_pj_trio_completar_homes)"
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$options $homes" -- "$current"))
    return 0
  fi

  if options="$(_pj_trio_row_field "$previous" 6)"; then
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$options" -- "$current"))
  fi
}

complete -F _pj_trio_completion pj-trio
