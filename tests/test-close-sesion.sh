#!/usr/bin/env bash
# Pruebas de cierre controlado de sesión herdr de un spec (#127):
# - ejecuta herdr session stop + delete solo si PR está mergeado y estado != needs-roberto
# - rechaza el cierre y conserva viva la sesión ante needs-roberto o PR sin merge
# - verifica que el prompt del PM cierra solo el workspace sin borrar la sesión
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PJ_TRIO_PM_PROMPT="$aqui/trio-pm-prompt.md"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pj="$tmp/HR-DEMO"
git init -q -b main "$pj"
git -C "$pj" remote add origin "https://github.com/acme/HR-DEMO.git"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
EOF

mkdir -p "$tmp/bin"

cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "pr view" ]]; then
  pr="$3"
  case "$pr" in
    *"/pull/101")
      echo '{"state":"MERGED","mergedAt":"2026-11-22T12:00:00Z"}'
      exit 0
      ;;
    *"/pull/102")
      echo '{"state":"OPEN","mergedAt":null}'
      exit 0
      ;;
    *"/pull/103")
      echo '{"state":"CLOSED","mergedAt":null}'
      exit 0
      ;;
  esac
fi
exit 1
STUB
chmod +x "$tmp/bin/gh"

cat >"$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_LOG"
case "${1:-} ${2:-}" in
  "session list")
    echo '{"sessions":[{"name":"123-spec-demo","running":true}]}'
    exit 0
    ;;
  "session stop"|"session delete")
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/herdr"

# 1. Caso feliz: estado hecho + PR mergeado -> stop + delete
mkdir -p "$pj/.trio/ravn-trio-123"
cat > "$pj/.trio/ravn-trio-123/status.json" <<'EOF'
{
  "ticket": "ravn-trio-123",
  "estado": "hecho",
  "paso": "cierre",
  "session": "123-spec-demo",
  "pr": "https://github.com/acme/ravn-trio/pull/101"
}
EOF

export HERDR_LOG="$tmp/herdr_ok.log"
: > "$HERDR_LOG"
PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" close "$pj" ravn-trio-123 >/dev/null
grep -q "^session stop 123-spec-demo$" "$HERDR_LOG" || fallo "no ejecutó herdr session stop: $(cat "$HERDR_LOG")"
grep -q "^session delete 123-spec-demo$" "$HERDR_LOG" || fallo "no ejecutó herdr session delete: $(cat "$HERDR_LOG")"

# 2. Inferencia de Home Repo desde $PWD y --ticket numérico único
export HERDR_LOG="$tmp/herdr_dry.log"
: > "$HERDR_LOG"
dry_out="$(cd "$pj" && PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" close 123 --dry-run)"
grep -q '\[dry-run\] herdr session stop "123-spec-demo"' <<<"$dry_out" || fallo "dry-run no mostró session stop"
grep -q '\[dry-run\] herdr session delete "123-spec-demo"' <<<"$dry_out" || fallo "dry-run no mostró session delete"
[[ ! -s "$HERDR_LOG" ]] || fallo "dry-run no debe invocar herdr"

# 3. Rechaza cierre si estado es needs-roberto (aunque el PR esté mergeado)
cat > "$pj/.trio/ravn-trio-123/status.json" <<'EOF'
{
  "ticket": "ravn-trio-123",
  "estado": "needs-roberto",
  "paso": "merge",
  "session": "123-spec-demo",
  "pr": "https://github.com/acme/ravn-trio/pull/101"
}
EOF
export HERDR_LOG="$tmp/herdr_nr.log"
: > "$HERDR_LOG"
if PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" close "$pj" ravn-trio-123 >/dev/null 2>&1; then
  fallo "debió rechazar el cierre en estado needs-roberto"
fi
if grep -qE "^session (stop|delete)" "$HERDR_LOG"; then
  fallo "en needs-roberto no debe detener ni eliminar la sesión"
fi

# 4. Rechaza cierre si PR está abierto (OPEN)
cat > "$pj/.trio/ravn-trio-123/status.json" <<'EOF'
{
  "ticket": "ravn-trio-123",
  "estado": "en-curso",
  "paso": "rv",
  "session": "123-spec-demo",
  "pr": "https://github.com/acme/ravn-trio/pull/102"
}
EOF
export HERDR_LOG="$tmp/herdr_open.log"
: > "$HERDR_LOG"
if PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" close "$pj" ravn-trio-123 >/dev/null 2>&1; then
  fallo "debió rechazar el cierre con PR OPEN"
fi
if grep -qE "^session (stop|delete)" "$HERDR_LOG"; then
  fallo "con PR OPEN no debe detener ni eliminar la sesión"
fi

# 5. Rechaza cierre si PR está CLOSED sin merge
cat > "$pj/.trio/ravn-trio-123/status.json" <<'EOF'
{
  "ticket": "ravn-trio-123",
  "estado": "hecho",
  "paso": "cierre",
  "session": "123-spec-demo",
  "pr": "https://github.com/acme/ravn-trio/pull/103"
}
EOF
export HERDR_LOG="$tmp/herdr_closed.log"
: > "$HERDR_LOG"
if PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" close "$pj" ravn-trio-123 >/dev/null 2>&1; then
  fallo "debió rechazar el cierre con PR CLOSED sin merge"
fi
if grep -qE "^session (stop|delete)" "$HERDR_LOG"; then
  fallo "con PR CLOSED sin merge no debe detener ni eliminar la sesión"
fi

# 6. El prompt del PM cierra solo el workspace y no elimina la sesión
k_spec="$(PATH="$tmp/bin:/usr/bin:/bin" "$aqui/pj-trio" --print-kickoff --spec "$pj" 123)"
grep -q 'herdr workspace close' <<<"$k_spec" || fallo "el prompt del PM debe cerrar su workspace"
grep -q 'sin detener ni eliminar la sesión' <<<"$k_spec" || fallo "el prompt del PM debe aclarar que no elimina la sesión"
if grep -q 'herdr session delete' <<<"$k_spec"; then
  fallo "el prompt del PM no debe ejecutar herdr session delete"
fi

echo "OK cierre de sesión herdr por Orquestador"
