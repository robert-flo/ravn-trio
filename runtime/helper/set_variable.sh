#!/usr/bin/env bash

# Shared repository, runtime and install paths for ravn-trio.
helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIO_RUNTIME_DIR="${TRIO_RUNTIME_DIR:-$(cd "$helper_dir/.." && pwd)}"
# Raíz del checkout o de la instalación: ahí viven trio-status, trio-pm-prompt.md
# y trio.conf.example junto al launcher pj-trio.
TRIO_ROOT="${TRIO_ROOT:-$(cd "$TRIO_RUNTIME_DIR/.." && pwd)}"
# Defaults del sistema (ver Makefile: SHAREDIR). Nada en $HOME.
TRIO_SHARE_DIR="${TRIO_SHARE_DIR:-/usr/share/ravn/trio}"

export TRIO_RUNTIME_DIR
export TRIO_ROOT
export TRIO_SHARE_DIR
