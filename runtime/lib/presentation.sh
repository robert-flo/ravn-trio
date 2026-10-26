#!/usr/bin/env bash

# Shared terminal presentation for git-setup.
# shellcheck disable=SC2317 # This library may be sourced or executed directly.
if [[ ${_GLOBAL_FN_SOURCED:-0} -eq 1 ]]; then
  return 0 2> /dev/null || exit 0
fi
readonly _GLOBAL_FN_SOURCED=1

# Disable styling automatically for pipes, CI, dumb terminals, and NO_COLOR.
if [[ -t 1 && ${TERM:-dumb} != "dumb" && -z ${NO_COLOR:-} ]]; then
  readonly RED=$'\033[0;31m'
  readonly GREEN=$'\033[0;32m'
  readonly YELLOW=$'\033[0;33m'
  readonly BLUE=$'\033[0;34m'
  readonly MAGENTA=$'\033[0;35m'
  readonly CYAN=$'\033[0;36m'
  readonly WHITE=$'\033[1;37m'
  readonly GRAY=$'\033[0;90m'
  # shellcheck disable=SC2034 # Public style constant used by sourced scripts.
  readonly LIGHT_GRAY=$'\033[0;37m'
  readonly NC=$'\033[0m'
  readonly ICON_CHECK="✓"
  readonly ICON_CROSS="✗"
  readonly ICON_ARROW="→"
  readonly ICON_WARN="⚠"
  readonly ICON_INFO=""
else
  readonly RED=""
  readonly GREEN=""
  readonly YELLOW=""
  readonly BLUE=""
  readonly MAGENTA=""
  readonly CYAN=""
  readonly WHITE=""
  readonly GRAY=""
  # shellcheck disable=SC2034 # Public style constant used by sourced scripts.
  readonly LIGHT_GRAY=""
  readonly NC=""
  readonly ICON_CHECK="[OK]"
  readonly ICON_CROSS="[ERROR]"
  readonly ICON_ARROW=">"
  readonly ICON_WARN="[WARN]"
  readonly ICON_INFO="[INFO]"
fi

# Semantic section icons used by git-setup.
# shellcheck disable=SC2034 # Public constants used by git-setup after source.
readonly \
  ICON_KEY="󰌋" \
  ICON_LOCK="" \
  ICON_GIT="" \
  ICON_GITHUB="" \
  ICON_GEAR="" \
  ICON_ROCKET="" \
  ICON_PACKAGE=""

# shellcheck disable=SC2034 # Public icon catalog used by git-setup after source.
declare -Ar RAVN_ICON=([documents_file]=" " [ui_check]=" " [ui_close]=" " [ui_command]=" " [ui_gear]=" " [ui_test]=" " [ui_trash]=" ")

print_header() {
  echo ""
  echo -e "${CYAN}╭────────────────────────────────────────────────────────────╮${NC}"
  echo -e "${CYAN}│${NC}  ${WHITE}$1${NC}"
  echo -e "${CYAN}╰────────────────────────────────────────────────────────────╯${NC}"
}

print_section() {
  echo ""
  echo -e "${MAGENTA}  $1${NC}"
  echo -e "${GRAY}  ──────────────────────────────────────────────────────────${NC}"
}

print_step() {
  echo -e "  ${GRAY}${ICON_ARROW}${NC} $1"
}

print_success() {
  echo -e "  ${GREEN}${ICON_CHECK}${NC} $1"
}

print_error() {
  echo -e "  ${RED}${ICON_CROSS}${NC} $1"
}

print_warn() {
  echo -e "  ${YELLOW}${ICON_WARN}${NC} $1"
}

print_info() {
  echo -e "  ${BLUE}${ICON_INFO}${NC} $1"
}
