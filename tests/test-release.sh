#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-test.XXXXXX")"
TEST_BIN="$TEST_ROOT/bin"
export STUB_DIR="$TEST_ROOT/stub"

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
SOURCE_REPO="robert-flo/ravn-trio"

# Disparos: push de tags v* y push a main que toca herdr-plugin.toml, con
# contents: write para crear el release con GITHUB_TOKEN.
[[ -f "$WORKFLOW" ]] || fail "workflow file does not exist: $WORKFLOW"
grep -qF -- '- "v*"' "$WORKFLOW" || fail 'the workflow must trigger on v* tag pushes'
grep -qF -- '- herdr-plugin.toml' "$WORKFLOW" || \
  fail 'the workflow must trigger on main pushes that change herdr-plugin.toml'
grep -qF 'contents: write' "$WORKFLOW" || fail 'the workflow needs contents: write'
# shellcheck disable=SC2016 # literal de YAML, no expansión de shell
grep -qF 'GH_TOKEN: ${{ github.token }}' "$WORKFLOW" || \
  fail 'the release must be created with GITHUB_TOKEN'
grep -qF 'secrets.ARCH_DISPATCH_TOKEN' "$WORKFLOW" || \
  fail 'the -arch dispatch token must come from the ARCH_DISPATCH_TOKEN secret'

# El cuerpo del paso (último run: | del archivo) es la lógica ejecutable: se
# extrae y se prueba con un gh de mentira que registra las llamadas.
script="$TEST_ROOT/release.sh"
awk '
  found {
    if ($0 ~ /^ {10}/) { sub(/^ {10}/, ""); print; next }
    if ($0 ~ /^[[:space:]]*$/) { next }
    exit
  }
  /^        run: \|$/ { found=1 }
' "$WORKFLOW" > "$script"
[[ -s "$script" ]] || fail 'could not extract the run script from the workflow'
bash -n "$script" || fail 'the extracted run script is not valid bash'

mkdir -p "$TEST_BIN" "$STUB_DIR"
# Estado del stub: STUB_RELEASES (tags con release, uno por línea),
# STUB_TAGS (tags existentes), STUB_CREATE_FAILS (create falla) y
# STUB_RACE (create falla pero el release aparece, como si otro run lo hubiera creado).
cat > "$TEST_BIN/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_DIR/gh-calls"
case "$1 $2" in
  "release view")
    if [[ -f "$STUB_DIR/created" ]] && grep -qxF "$3" "$STUB_DIR/created"; then exit 0; fi
    grep -qxF "$3" <<<"${STUB_RELEASES:-}" && exit 0
    exit 1 ;;
  "release list")
    [[ -n ${STUB_RELEASES:-} ]] && printf '%s\n' "$STUB_RELEASES"
    exit 0 ;;
  "release create")
    if [[ -n ${STUB_RACE:-} ]]; then printf '%s\n' "$3" >>"$STUB_DIR/created"; exit 1; fi
    [[ -n ${STUB_CREATE_FAILS:-} ]] && exit 1
    printf '%s\n' "$3" >>"$STUB_DIR/created"
    exit 0 ;;
esac
if [[ $1 == api && $2 == repos/*/git/ref/tags/* ]]; then
  grep -qxF "${2##*/}" <<<"${STUB_TAGS:-}" && exit 0
  exit 1
fi
if [[ $1 == api && $2 == repos/*/dispatches ]]; then
  printf 'token=%s\n' "$GH_TOKEN" >>"$STUB_DIR/gh-calls"
  exit 0
fi
echo "llamada inesperada: $*" >&2
exit 1
STUB
chmod +x "$TEST_BIN/gh"

WS="$TEST_ROOT/ws"
mkdir -p "$WS"

run_release() { # run_release <ref_type> <ref_name> <manifest_version>; env STUB_* y DISPATCH_TOKEN
  : > "$STUB_DIR/gh-calls"
  rm -f "$STUB_DIR/created"
  printf 'id = "ravn.trio"\nversion = "%s"\n' "$3" > "$WS/herdr-plugin.toml"
  # Aislado: el PATH del script tiene el gh de mentira y solo lo básico.
  ( cd "$WS" && PATH="$TEST_BIN:/usr/bin:/bin" \
    GITHUB_REPOSITORY="$SOURCE_REPO" GITHUB_SHA=abc123 \
    GITHUB_REF_TYPE="$1" GITHUB_REF_NAME="$2" \
    GH_TOKEN=ghs_actions ARCH_DISPATCH_TOKEN="${DISPATCH_TOKEN-arch_token}" \
    /bin/bash "$script" ) >"$TEST_ROOT/out" 2>&1
}
calls() { cat "$STUB_DIR/gh-calls"; }

# Caso: push del tag nuevo → release sobre el tag existente, latest, y despacho a -arch con su token.
STUB_RELEASES=$'v0.1.3\nv0.1.7' STUB_TAGS='v0.1.8' run_release tag v0.1.8 0.1.8 || fail "tag push: $(cat "$TEST_ROOT/out")"
calls | grep -qF 'release create v0.1.8 -R robert-flo/ravn-trio --verify-tag --title ravn-trio 0.1.8 --generate-notes --latest=true' || \
  fail "tag push must create a latest release on the pushed tag: $(calls)"
calls | grep -qF 'api repos/robert-flo/ravn-trio-arch/dispatches -f event_type=upstream-released -f client_payload[tag]=v0.1.8' || \
  fail "a new latest release must dispatch upstream-released to the -arch repo: $(calls)"
calls | grep -qxF 'token=arch_token' || fail 'the -arch dispatch must use ARCH_DISPATCH_TOKEN'

# Caso: push a main con versión nueva y sin tag → el release crea el tag en el commit del merge.
STUB_RELEASES='v0.1.7' STUB_TAGS='' run_release branch main 0.1.8 || fail "main push: $(cat "$TEST_ROOT/out")"
calls | grep -qF 'release create v0.1.8 -R robert-flo/ravn-trio --target abc123' || \
  fail "a main push without the tag must create it at GITHUB_SHA: $(calls)"

# Caso: el release ya existe → no crea ni despacha.
STUB_RELEASES=$'v0.1.7\nv0.1.8' STUB_TAGS='v0.1.8' run_release tag v0.1.8 0.1.8 || fail "existing: $(cat "$TEST_ROOT/out")"
! calls | grep -qF 'release create' || fail 'an existing release must not be recreated'
! calls | grep -qF 'dispatches' || fail 'an existing release must not dispatch'

# Caso: tag viejo empujado tarde → release sin latest y sin despacho.
STUB_RELEASES=$'v0.1.3\nv0.1.7' STUB_TAGS='v0.1.5' run_release tag v0.1.5 0.1.7 || fail "old tag: $(cat "$TEST_ROOT/out")"
calls | grep -qF -- '--latest=false' || fail "an older version must not take latest: $(calls)"
! calls | grep -qF 'dispatches' || fail 'an older version must not dispatch'

# Caso: 0.1.10 es más nueva que 0.1.9 (sort -V, no orden de bytes).
STUB_RELEASES='v0.1.9' STUB_TAGS='v0.1.10' run_release tag v0.1.10 0.1.10 || fail "0.1.10: $(cat "$TEST_ROOT/out")"
calls | grep -qF -- '--latest=true' || fail "v0.1.10 must be latest over v0.1.9: $(calls)"

# Caso: carrera con el otro disparo → create falla pero el release existe: éxito sin despacho.
STUB_RELEASES='v0.1.7' STUB_TAGS='v0.1.8' STUB_RACE=1 run_release tag v0.1.8 0.1.8 || fail "race: $(cat "$TEST_ROOT/out")"
! calls | grep -qF 'dispatches' || fail 'the losing run of a race must not dispatch'

# Caso: create falla de verdad → el job falla.
if STUB_RELEASES='v0.1.7' STUB_TAGS='v0.1.8' STUB_CREATE_FAILS=1 run_release tag v0.1.8 0.1.8; then
  fail 'a failed release creation must fail the job'
fi

# Caso: sin token de -arch → release creado, sin despacho y sin fallo (el cron diario lo toma).
STUB_RELEASES='v0.1.7' STUB_TAGS='v0.1.8' DISPATCH_TOKEN='' run_release tag v0.1.8 0.1.8 || fail "no token: $(cat "$TEST_ROOT/out")"
calls | grep -qF 'release create v0.1.8' || fail 'without the -arch token the release is still created'
! calls | grep -qF 'dispatches' || fail 'without the -arch token there is no dispatch'

# Caso: tag que no es vN.N.N → falla sin crear nada.
if STUB_RELEASES='' STUB_TAGS='' run_release tag v1.0-rc1 0.1.8; then
  fail 'a non-stable tag must fail'
fi
! calls | grep -qF 'release create' || fail 'a non-stable tag must not create a release'

echo 'ok release'
