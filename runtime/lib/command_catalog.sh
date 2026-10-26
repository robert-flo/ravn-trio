#!/usr/bin/env bash

if [[ ${GIT_SETUP_COMMAND_CATALOG_LOADED:-0} == 1 ]]; then
  return 0
fi
readonly GIT_SETUP_COMMAND_CATALOG_LOADED=1

# Load the language-neutral command contract shared by dispatch, menu, help,
# and shell completion. Fields: canonical<TAB>aliases<TAB>label<TAB>description<TAB>icon<TAB>menu<TAB>options.
GIT_SETUP_COMMAND_CATALOG_DIR=""
GIT_SETUP_COMMAND_CATALOG_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly GIT_SETUP_COMMAND_CATALOG_DIR
readonly GIT_SETUP_COMMAND_CATALOG_FILE="${GIT_SETUP_COMMAND_CATALOG_FILE:-$GIT_SETUP_COMMAND_CATALOG_DIR/../commands.tsv}"
# shellcheck disable=SC2034 # Public catalog consumed by sourced capabilities.
GIT_SETUP_COMMAND_CATALOG=()
while IFS= read -r catalog_record || [[ -n $catalog_record ]]; do
  [[ -z $catalog_record || ${catalog_record:0:1} == "#" ]] && continue
  GIT_SETUP_COMMAND_CATALOG+=("$catalog_record")
done < "$GIT_SETUP_COMMAND_CATALOG_FILE"
readonly GIT_SETUP_COMMAND_CATALOG

command_catalog_get() {
  local lookup="$1"
  local requested_field="$2"
  local record=""
  local canonical=""
  local aliases=""
  local label=""
  local description=""
  local icon=""
  local menu=""
  local options=""
  local value=""

  for record in "${GIT_SETUP_COMMAND_CATALOG[@]}"; do
    IFS=$'\t' read -r canonical aliases label description icon menu options <<< "$record"
    if [[ $canonical == "$lookup" || " $aliases " == *" $lookup "* ]]; then
      case "$requested_field" in
        canonical) value="$canonical" ;;
        aliases) value="$aliases" ;;
        label) value="$label" ;;
        description) value="$description" ;;
        icon) value="$icon" ;;
        menu) value="$menu" ;;
        options) value="$options" ;;
        module) value="$canonical" ;;
        *)
          GIT_SETUP_COMMAND_CATALOG_ERROR="Unknown metadata field: $requested_field"
          return 1
          ;;
      esac
      # shellcheck disable=SC2034 # Read by the caller in the same shell.
      GIT_SETUP_COMMAND_CATALOG_VALUE="$value"
      return 0
    fi
  done

  # shellcheck disable=SC2034 # Read by the caller in the same shell.
  GIT_SETUP_COMMAND_CATALOG_ERROR="Unknown command: $lookup"
  return 1
}

command_catalog_list() {
  local include_menu="$1"
  local record=""
  local canonical=""
  local aliases=""
  local label=""
  local description=""
  local icon=""
  local menu=""
  local options=""

  for record in "${GIT_SETUP_COMMAND_CATALOG[@]}"; do
    IFS=$'\t' read -r canonical aliases label description icon menu options <<< "$record"
    if [[ $include_menu == all || $menu == 1 ]]; then
      printf '%s\n' "$canonical"
    fi
  done
}

command_catalog_completion_words() {
  local record=""
  local canonical=""
  local aliases=""
  local label=""
  local description=""
  local icon=""
  local menu=""
  local options=""

  for record in "${GIT_SETUP_COMMAND_CATALOG[@]}"; do
    IFS=$'\t' read -r canonical aliases label description icon menu options <<< "$record"
    printf '%s %s\n' "$canonical" "$aliases"
  done
}
