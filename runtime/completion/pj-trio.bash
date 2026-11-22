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

_pj_trio_completion() {
  local current="${COMP_WORDS[COMP_CWORD]}"
  local previous="${COMP_WORDS[COMP_CWORD - 1]:-}"
  local commands=""
  local options=""

  if ((COMP_CWORD == 1)); then
    commands=$(command_catalog_completion_words)
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$commands" -- "$current"))
    return 0
  fi

  if options="$(_pj_trio_row_field "$previous" 6)"; then
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$options" -- "$current"))
  fi
}

complete -F _pj_trio_completion pj-trio
