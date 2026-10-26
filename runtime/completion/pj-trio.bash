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

  if command_catalog_get "$previous" options; then
    options="$GIT_SETUP_COMMAND_CATALOG_VALUE"
    # shellcheck disable=SC2207 # Bash completion requires word splitting here.
    COMPREPLY=($( compgen -W "$options" -- "$current"))
  fi
}

complete -F _pj_trio_completion pj-trio
