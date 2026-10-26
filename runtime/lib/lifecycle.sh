#!/usr/bin/env bash

# Runtime lifecycle cleanup shared by the root launcher and future entrypoints.
cleanup_runtime() {
  trap - SIGINT SIGTERM ERR EXIT
  if [[ -f /tmp/gpg_batch ]]; then
    rm -f /tmp/gpg_batch
  fi
}
