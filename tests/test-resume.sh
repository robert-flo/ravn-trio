#!/usr/bin/env bash
# Pruebas de `pj-trio resume` (alias r): guarda de lease/estado, prompt de relevo, herdr y status.json.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export TRIO_SHARE_DIR="$tmp/no-share" TRIO_OVERRIDE_DIR="$tmp/no-zt"
export TRIO_PANE_SETTLE_SECS="0" TRIO_READY_TIMEOUT="2" TRIO_READY_INTERVAL="0"
unset PJ_TRIO_CONFIG TRIO_LEASE_MINUTES

# Meta-repo y repo miembro con worktree real
pj="$tmp/HR-DEMO"
miembro="$tmp/miembro-repo"
wt="$pj/repos/miembro-repo/230-demo"
mkdir -p "$pj/.trio/miembro-repo-230" "$miembro" "$wt"

git init -q "$pj"
git -C "$pj" config user.name "Test"
git -C "$pj" config user.email "test@example.com"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
repos:
  - repo: "robert-flo/miembro-repo"
    dir: "../miembro-repo"
EOF

git init -q "$miembro"
git -C "$miembro" config user.name "Test"
git -C "$miembro" config user.email "test@example.com"
git -C "$miembro" remote add origin "https://github.com/robert-flo/miembro-repo.git"
echo "hola" > "$miembro/README.md"
git -C "$miembro" add README.md
git -C "$miembro" commit -q -m "init"

git -C "$miembro" worktree add -q -b issue/230-demo "$wt" HEAD
echo "cambio-en-curso" >> "$wt/README.md"

cat > "$pj/.trio/miembro-repo-230/HANDOFF.md" <<'EOF'
- Hecho: esqueleto del comando.
- Falta: conectar pruebas con stubs.
- Siguiente: correr make check.
EOF

cat > "$pj/.trio/miembro-repo-230/kickoff.md" <<'EOF'
Kickoff original del ticket 230.
EOF

# Stubs de herdr y gh controlados por archivo de modo
mkdir -p "$tmp/bin"
herdr_log="$tmp/herdr.log"
mode_file="$tmp/herdr_mode"
echo "vivo" > "$mode_file"

cat > "$tmp/bin/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$herdr_log"
mode="\$(cat "$mode_file")"
case "\${1:-} \${2:-}" in
  "workspace list")
    if [[ "\$mode" == "no-ws" ]]; then
      echo '{"result":{"workspaces":[]}}'
    else
      echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"trio HR-DEMO/miembro-repo#230"}]}}'
    fi
    ;;
  "agent list")
    echo '{"result":{"agents":[{"name":"wk-miembro-repo-230","agent_status":"running","workspace_id":"w1","pane_id":"p2"}]}}'
    ;;
  "agent get")
    case "\$mode" in
      vivo)
        echo '{"result":{"agent":{"name":"wk-miembro-repo-230","agent_status":"running","interactive_ready":true,"workspace_id":"w1","pane_id":"p2"}}}'
        ;;
      sin-cuota)
        echo '{"result":{"agent":{"name":"wk-miembro-repo-230","agent_status":"idle","interactive_ready":true,"workspace_id":"w1","pane_id":"p2"}}}'
        ;;
      muerto)
        echo '{"result":{"agent":{"name":"wk-miembro-repo-230","agent_status":"exited","workspace_id":"w1","pane_id":"p2"}}}'
        ;;
      ready-agy)
        echo '{"result":{"agent":{"name":"wk-miembro-repo-230","agent_status":"idle","interactive_ready":true,"workspace_id":"w1","pane_id":"p2"}}}'
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  "agent read")
    if [[ "\$mode" == "sin-cuota" ]]; then
      echo "Error 429: quota exceeded"
    elif [[ "\$mode" == "ready-agy" ]]; then
      echo ">"
    else
      echo "working..."
    fi
    ;;
  "tab list")
    echo '{"result":{"tabs":[{"tab_id":"t1","label":"pm"},{"tab_id":"t2","label":"wk"}]}}'
    ;;
  "pane list")
    echo '{"result":{"panes":[{"pane_id":"p1","tab_id":"t1"},{"pane_id":"p2","tab_id":"t2"}]}}'
    ;;
  "pane create")
    echo '{"result":{"pane":{"pane_id":"p2_new"}}}'
    ;;
  "workspace create")
    echo '{"result":{"workspace":{"workspace_id":"w_new"},"tab":{"tab_id":"t_new"},"root_pane":{"pane_id":"p_new"}}}'
    ;;
  "pane close"|"pane rename"|"tab rename"|"tab create"|"agent start"|"agent prompt")
    echo '{"ok":true}'
    ;;
  *)
    echo '{"ok":true}'
    ;;
esac
EOF
chmod +x "$tmp/bin/herdr"

cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "pr view" ]]; then
  echo '{"number":77,"url":"https://github.com/robert-flo/miembro-repo/pull/77","state":"OPEN","title":"PR demo 230","reviewDecision":"REVIEW_REQUIRED","headRefName":"issue/230-demo"}'
elif [[ "${1:-} ${2:-}" == "pr list" ]]; then
  echo '[{"number":77,"url":"https://github.com/robert-flo/miembro-repo/pull/77","state":"OPEN","title":"PR demo 230","reviewDecision":"REVIEW_REQUIRED","headRefName":"issue/230-demo"}]'
fi
EOF
chmod +x "$tmp/bin/gh"

future_iso="$(date -d "+30 minutes" --iso-8601=seconds)"
past_iso="$(date -d "-30 minutes" --iso-8601=seconds)"
now_iso="$(date --iso-8601=seconds)"

write_status() {
  local lease="$1"
  cat > "$pj/.trio/miembro-repo-230/status.json" <<EOF
{
  "ticket": "miembro-repo-230",
  "estado": "en-curso",
  "paso": "wk",
  "owner": "wk-miembro-repo-230",
  "worktree": "$wt",
  "pr": "https://github.com/robert-flo/miembro-repo/pull/77",
  "heartbeat_at": "$now_iso",
  "lease_expires_at": "$lease",
  "timestamp": "$now_iso"
}
EOF
}

# 1. --help y alias r
help_out="$("$aqui/pj-trio" resume --help)"
grep -qF -- '--print-resume' <<<"$help_out" || fallo "--help no documenta --print-resume"

# 2. Rechaza cuando estado_real == vivo y lease vigente sin --force
echo "vivo" > "$mode_file"
write_status "$future_iso"
if PATH="$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind cursor 2>"$tmp/err_vivo"; then
  fallo "debió rechazar cuando estado_real == vivo sin --force"
fi
grep -qi "sigue vivo" "$tmp/err_vivo" || fallo "mensaje inesperado al rechazar vivo: $(cat "$tmp/err_vivo")"

# 3. --print-resume ensambla HANDOFF.md, status.json, contexto git, PR y kickoff.md
echo "sin-cuota" > "$mode_file"
prompt_out="$(PATH="$tmp/bin:$PATH" "$aqui/pj-trio" r "$pj" 230 --repo "$miembro" --kind cursor --print-resume)"
grep -qF -- 'esqueleto del comando' <<<"$prompt_out" || fallo "falta HANDOFF.md en prompt"
grep -qF -- 'miembro-repo-230' <<<"$prompt_out" || fallo "falta status.json en prompt"
grep -qF -- 'issue/230-demo' <<<"$prompt_out" || fallo "falta rama git en prompt"
grep -qF -- 'README.md' <<<"$prompt_out" || fallo "falta diff/status git en prompt"
grep -qF -- 'PR #77: PR demo 230 [OPEN]' <<<"$prompt_out" || fallo "falta estado del PR en prompt"
grep -qF -- 'Kickoff original del ticket 230.' <<<"$prompt_out" || fallo "falta kickoff.md en prompt"

# 4. Relevo inmediato en sin-cuota con --kind cursor, reemplaza panel en herdr y actualiza owner + lease_expires_at
: > "$herdr_log"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind cursor --role wk >/dev/null
grep -qF -- 'pane create --tab t2 --cwd '"$miembro" "$herdr_log" || fallo "no creó pane con --cwd miembro: $(cat "$herdr_log")"
grep -qF -- 'pane close p2' "$herdr_log" || fallo "no cerró pane previo p2"
grep -qE "agent start wk-miembro-repo-230 --kind cursor --pane p2_new -- .*--workspace $miembro --add-dir $pj" "$herdr_log" \
  || fallo "no arrancó cursor con --workspace miembro y --add-dir meta-repo: $(cat "$herdr_log")"
jq -e '.owner == "wk-miembro-repo-230" and (.lease_expires_at // "") != ""' "$pj/.trio/miembro-repo-230/status.json" >/dev/null \
  || fallo "status.json no actualizó owner y lease_expires_at"

# 5. Relevo con lease vencido aunque herdr diga vivo (sin --force)
echo "vivo" > "$mode_file"
write_status "$past_iso"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind cursor >/dev/null \
  || fallo "debió permitir relevo con lease vencido"

# 6. Relevo con --force cuando está vivo y lease vigente
echo "vivo" > "$mode_file"
write_status "$future_iso"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind cursor --force >/dev/null \
  || fallo "debió permitir relevo con --force"

# 7. Relevo cuando está muerto
echo "muerto" > "$mode_file"
write_status "$future_iso"
: > "$herdr_log"
PATH="$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind cursor --role wk >/dev/null
grep -qF -- 'agent start wk-miembro-repo-230 --kind cursor' "$herdr_log" \
  || fallo "no lanzó relevo cuando estado_real == muerto"

# 8. Relevo cuando no hay workspace en herdr (crea workspace) con --kind agy
echo "no-ws" > "$mode_file"
write_status "$future_iso"
: > "$herdr_log"
# Tras workspace create, herdr pasa a ready-agy para que esperar_agente_listo + agent prompt pasen
mkdir -p "$tmp/bin_agy"
cat > "$tmp/bin_agy/herdr" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-}" == "workspace create" ]]; then
  echo "ready-agy" > "$mode_file"
fi
exec "$tmp/bin/herdr" "\$@"
EOF
chmod +x "$tmp/bin_agy/herdr"
PATH="$tmp/bin_agy:$tmp/bin:$PATH" "$aqui/pj-trio" resume "$pj" 230 --repo "$miembro" --kind agy --role wk >/dev/null
grep -qF -- 'workspace create --cwd '"$miembro" "$herdr_log" \
  || fallo "no creó workspace cuando faltaba: $(cat "$herdr_log")"
grep -qF -- 'agent start wk-miembro-repo-230 --kind agy --pane p_new -- --agent WK-HR-DEMO --add-dir '"$pj" "$herdr_log" \
  || fallo "no arrancó agy con --agent y --add-dir: $(cat "$herdr_log")"
grep -qF -- 'agent prompt wk-miembro-repo-230' "$herdr_log" \
  || fallo "no envió prompt de relevo a agy: $(cat "$herdr_log")"

echo "OK resume"
