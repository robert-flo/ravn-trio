#!/usr/bin/env bash
# Pruebas de pj-trio con flag --oneshot: dry-run, kickoff, fleet y watch.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/pj-demo"
git init -q "$tmp/miembro"
export PJ_TRIO_CONFIG="$aqui/trio.conf.example"
export PATH="/usr/bin:/bin"

fallo() { echo "FALLO: $*" >&2; exit 1; }

# 1. --dry-run con --oneshot
out="$("$aqui/pj-trio" --dry-run "$tmp/pj-demo" 42 --repo "$tmp/miembro" --oneshot 2>&1)"

grep -q 'herdr agent start "os-miembro-42"' <<<"$out" || fallo "nombre de agente OS incorrecto"
grep -q -- '--agent "OS-pj-demo"' <<<"$out" || fallo "agente OS-<proyecto> incorrecto"
grep -q 'herdr tab rename "<id_tab_os>" os' <<<"$out" || fallo "no renombró tab a os"
grep -q 'herdr pane rename "<id_pane_os>" "OS-42"' <<<"$out" || fallo "no renombró pane a OS-42"
grep -q 'Kinds: OS=' <<<"$out" || fallo "no reportó Kinds: OS="
if grep -qE 'herdr tab rename "<id_tab_pm>"|herdr tab create .* wk|herdr tab create .* rv' <<<"$out"; then
    fallo "oneshot creó tabs de wk/rv/pm"
fi
if grep -q 'agent start "pm-' <<<"$out" || grep -q 'agent start "wk-' <<<"$out" || grep -q 'agent start "rv-' <<<"$out"; then
    fallo "oneshot inició agentes pm/wk/rv"
fi
grep -q -- '-i "Lee y segui al pie de la letra las instrucciones de arranque del archivo ' <<<"$out" || fallo "arranque vía agy -i para OS"

# 2. --print-kickoff con --oneshot
k="$("$aqui/pj-trio" --print-kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro" --oneshot)"
grep -q '{{' <<<"$k" && fallo "quedan placeholders en trio-os-prompt"
grep -q "agente oneshot (OS)" <<<"$k" || fallo "no es el prompt de OS"
grep -q "$tmp/pj-demo/.trio/miembro-42" <<<"$k" || fallo "carpeta de handoff errónea"
grep -q "os.md" <<<"$k" || fallo "falta referencia a os.md"
grep -q "Door: two-way" <<<"$k" || fallo "falta regla Door: two-way"
grep -q "Blast Radius: Low" <<<"$k" || fallo "falta regla Blast Radius: Low"
grep -q "herdr workspace close" <<<"$k" || fallo "falta herdr workspace close"

# 3. subcomando kickoff con --oneshot
k2="$("$aqui/pj-trio" kickoff "$tmp/pj-demo" 42 --repo "$tmp/miembro" --oneshot)"
[[ "$k" == "$k2" ]] || fallo "subcomando kickoff --oneshot no coincide con start --print-kickoff --oneshot"

# 4. Fleet y Watch reconocen agente os-*
pj_fleet="$tmp/HR-FLEET"
git init -q "$pj_fleet"
cat > "$pj_fleet/proyecto.yml" <<'EOF'
proyecto: HR-FLEET
EOF

mkdir -p "$pj_fleet/.trio/ravn-trio-53"
cat > "$pj_fleet/.trio/ravn-trio-53/status.json" <<'EOF'
{
  "ticket": "ravn-trio-53",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "2026-11-17T12:00:00-06:00"
}
EOF

# Mock herdr con agente os-ravn-trio-53 (sin pm-*)
mkdir -p "$tmp/bin_herdr"
cat > "$tmp/bin_herdr/herdr" <<'EOF'
#!/bin/sh
if [ "$1" = "workspace" ] && [ "$2" = "list" ]; then
  cat <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w-os-1","label":"trio HR-FLEET/ravn-trio#53"}]}}
JSON
  exit 0
fi
if [ "$1" = "agent" ] && [ "$2" = "get" ]; then
  name="$3"
  if [ "$name" = "os-ravn-trio-53" ]; then
    cat <<'JSON'
{"result":{"agent":{"name":"os-ravn-trio-53","agent_status":"running","workspace_id":"w-os-1"}}}
JSON
    exit 0
  fi
  echo '{"error":{"code":"agent_not_found"}}'
  exit 1
fi
exit 0
EOF
chmod +x "$tmp/bin_herdr/herdr"

json_fleet="$(PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet "$pj_fleet" --json)"
jq -e '.[] | select(.clave == "ravn-trio-53") | .pm_herdr_status == "running" and .workspace_id == "w-os-1"' <<<"$json_fleet" >/dev/null \
  || fallo "fleet no resolvió agente os-trio-53: $json_fleet"

echo "OK oneshot"
