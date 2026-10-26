#!/usr/bin/env bash

# Resolve a public command name and execute its autonomous command module.
dispatch_command() {
  local command="${1:-}"
  local canonical=""
  local script=""

  command_catalog_get "$command" canonical || {
    print_error "$GIT_SETUP_COMMAND_CATALOG_ERROR"
    return 2
  }
  canonical="$GIT_SETUP_COMMAND_CATALOG_VALUE"
  script="$PROJECT_DIR/scripts/$canonical"

  if [[ ! -x $script ]]; then
    print_error "Command module is not executable: $script"
    return 1
  fi

  shift
  "$script" "$@"
}
