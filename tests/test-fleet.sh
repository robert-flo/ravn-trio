#!/usr/bin/env bash
# Pruebas de `pj-trio fleet`: tabla, --json, --activos, alias fl y degradación sin herdr.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

# Proyecto temporal con 4 estados distintos en .trio/*/status.json
pj="$tmp/HR-DEMO"
git init -q "$pj"
cat > "$pj/proyecto.yml" <<'EOF'
proyecto: HR-DEMO
EOF

mkdir -p \
  "$pj/.trio/ravn-trio-10" \
  "$pj/.trio/ravn-trio-11" \
  "$pj/.trio/ravn-trio-12" \
  "$pj/.trio/13"

cat > "$pj/.trio/ravn-trio-10/status.json" <<'EOF'
{
  "ticket": "ravn-trio-10",
  "estado": "hecho",
  "paso": "cierre",
  "timestamp": "2026-11-17T08:00:00-06:00",
  "pr": "https://github.com/o/r/pull/10",
  "head": "aaa1111",
  "merge_danger": "two-way / Low"
}
EOF

cat > "$pj/.trio/ravn-trio-11/status.json" <<'EOF'
{
  "ticket": "ravn-trio-11",
  "estado": "en-curso",
  "paso": "wk",
  "timestamp": "2026-11-17T09:00:00-06:00",
  "pr": "https://github.com/o/r/pull/11",
  "head": "bbb2222"
}
EOF

cat > "$pj/.trio/ravn-trio-12/status.json" <<'EOF'
{
  "ticket": "ravn-trio-12",
  "estado": "needs-roberto",
  "paso": "merge",
  "timestamp": "2026-11-17T09:30:00-06:00",
  "pr": "https://github.com/o/r/pull/12",
  "head": "ccc3333",
  "merge_danger": "two-way / High"
}
EOF

# Ticket hecho pero con workspace aún abierto en herdr (debe aparecer en --activos)
cat > "$pj/.trio/13/status.json" <<'EOF'
{
  "ticket": "13",
  "estado": "hecho",
  "paso": "cierre",
  "timestamp": "2026-11-17T09:45:00-06:00"
}
EOF

# Stub de herdr
mkdir -p "$tmp/bin_herdr"
cat > "$tmp/bin_herdr/herdr" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "workspace list")
    cat <<'JSON'
{"id":"cli:workspace:list","result":{"workspaces":[
  {"workspace_id":"w2","label":"trio HR-DEMO/ravn-trio#11"},
  {"workspace_id":"w3","label":"trio HR-DEMO/ravn-trio#12"},
  {"workspace_id":"w4","label":"trio HR-DEMO#13"}
]}}
JSON
    ;;
  "agent get")
    case "${3:-}" in
      pm-ravn-trio-11)
        echo '{"id":"cli:agent:get","result":{"agent":{"name":"pm-ravn-trio-11","agent_status":"running","workspace_id":"w2"}}}'
        ;;
      pm-ravn-trio-12)
        echo '{"id":"cli:agent:get","result":{"agent":{"name":"pm-ravn-trio-12","agent_status":"idle","workspace_id":"w3"}}}'
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin_herdr/herdr"

# 1. Salida tabla por defecto y alias fl
tabla="$(PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet "$pj")"
grep -q 'Fleet — HR-DEMO (4)' <<<"$tabla" || fallo "encabezado tabla inesperado: $tabla"
grep -q 'ravn-trio-10' <<<"$tabla" || fallo "falta ravn-trio-10 en tabla"
grep -q 'ravn-trio-11' <<<"$tabla" || fallo "falta ravn-trio-11 en tabla"
grep -q 'two-way / High' <<<"$tabla" || fallo "falta merge_danger en tabla"

tabla_alias="$(PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fl "$pj")"
[[ "$tabla" == "$tabla_alias" ]] || fallo "alias fl difiere de fleet"

# 2. --json completo con los 10 campos requeridos
json_all="$(PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet "$pj" --json)"
jq -e 'length == 4' <<<"$json_all" >/dev/null || fallo "esperaba 4 elementos en --json: $json_all"
jq -e '
  (.[] | select(.clave == "ravn-trio-10") |
    .ticket == "ravn-trio-10" and .estado == "hecho" and .paso == "cierre" and
    .pm_herdr_status == "cerrado" and .workspace_id == "" and
    .pr == "https://github.com/o/r/pull/10" and .head == "aaa1111" and
    .merge_danger == "two-way / Low" and .timestamp == "2026-11-17T08:00:00-06:00")
  and
  (.[] | select(.clave == "ravn-trio-11") |
    .pm_herdr_status == "running" and .workspace_id == "w2")
  and
  (.[] | select(.clave == "ravn-trio-12") |
    .estado == "needs-roberto" and .pm_herdr_status == "idle" and .workspace_id == "w3")
' <<<"$json_all" >/dev/null || fallo "campos JSON incorrectos: $json_all"

# 3. --activos filtra en-curso, needs-roberto o workspace abierto
json_act="$(PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet "$pj" --activos --json)"
jq -e 'length == 3' <<<"$json_act" >/dev/null || fallo "--activos esperaba 3 elementos: $json_act"
if jq -e '.[] | select(.clave == "ravn-trio-10")' <<<"$json_act" >/dev/null; then
  fallo "ravn-trio-10 (hecho sin workspace) no debía aparecer en --activos"
fi
jq -e '.[] | select(.clave == "13" and .workspace_id == "w4")' <<<"$json_act" >/dev/null \
  || fallo "ticket 13 con workspace abierto debía aparecer en --activos"

# 4. Degradación limpia sin herdr en PATH
mkdir -p "$tmp/bin_noherdr"
for cmd in bash sh dirname basename realpath cat date jq sed awk tr sha1sum cut grep head tput; do
  if bin_path="$(command -v "$cmd" 2>/dev/null)"; then
    ln -sf "$bin_path" "$tmp/bin_noherdr/$cmd"
  fi
done

json_noherdr="$(PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet "$pj" --json)"
jq -e 'length == 4 and all(.[]; .pm_herdr_status == "unavailable" and .workspace_id == "")' <<<"$json_noherdr" >/dev/null \
  || fallo "degradación sin herdr falló: $json_noherdr"

# 5. Proyecto sin .trio
pj_vacio="$tmp/HR-VACIO"
git init -q "$pj_vacio"
json_vacio="$(PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet "$pj_vacio" --json)"
jq -e '. == []' <<<"$json_vacio" >/dev/null || fallo "proyecto vacío debía devolver []: $json_vacio"

# 6. Sin <proyecto>: el Home Repo sale del cwd (o de un ancestro).
json_cwd="$(cd "$pj" && PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet --json)"
[[ "$json_cwd" == "$json_all" ]] || fallo "fleet sin args en el Home Repo debía igualar a la ruta: $json_cwd"
json_sub="$(cd "$pj/.trio/ravn-trio-11" && PATH="$tmp/bin_herdr:$PATH" "$aqui/pj-trio" fleet --activos --json)"
[[ "$json_sub" == "$json_act" ]] || fallo "fleet --activos desde un subdirectorio debía igualar al argumento: $json_sub"
# .trio/ sin proyecto.yml también calza si el directorio es HR-* o pj-*.
pj_solo_trio="$tmp/HR-SOLO-TRIO"
git init -q "$pj_solo_trio"
mkdir -p "$pj_solo_trio/.trio"
json_solo="$(cd "$pj_solo_trio" && PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet --json)"
jq -e '. == []' <<<"$json_solo" >/dev/null || fallo "HR-* con solo .trio/ debía resolver: $json_solo"

# 7. Fuera de un Home Repo, o ambiguo, pide <proyecto>.
rc=0
err="$(cd "$tmp" && PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet --json 2>&1)" || rc=$?
[[ "$rc" -ne 0 ]] || fallo "fuera de un Home Repo fleet debía fallar"
grep -q '<proyecto>' <<<"$err" || fallo "el error debía pedir <proyecto>: $err"
pj_amb="$tmp/HR-UNO"
mkdir -p "$pj_amb"
printf 'proyecto: "HR-DOS"\n' > "$pj_amb/proyecto.yml"
rc=0
err="$(cd "$pj_amb" && PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet 2>&1)" || rc=$?
[[ "$rc" -ne 0 ]] || fallo "nombre HR-* distinto de proyecto: debía ser ambiguo"
grep -q '<proyecto>' <<<"$err" || fallo "el ambiguo debía pedir <proyecto>: $err"

# 8. Con argumento, el cwd no importa.
json_explicito="$(cd / && PATH="$tmp/bin_noherdr" "$aqui/pj-trio" fleet "$pj" --json)"
[[ "$json_explicito" == "$json_noherdr" ]] || fallo "con <proyecto> el cwd no debía cambiar el resultado"

# 9. Ayuda y completion: <proyecto> opcional y nombres HR-*/pj-*.
"$aqui/pj-trio" fleet --help | grep -q 'Si se omite' \
  || fallo "pj-trio fleet --help debe decir que <proyecto> se puede omitir"
comp_out="$(PJ_TRIO_ROOTS="$tmp" bash -c '
  source "'"$aqui"'/runtime/completion/pj-trio.bash"
  COMP_WORDS=(pj-trio fleet "")
  COMP_CWORD=2
  _pj_trio_completion
  printf "%s\n" "${COMPREPLY[@]}"
')"
grep -qx -- '--activos' <<<"$comp_out" || fallo "completion de fleet debe incluir --activos: $comp_out"
grep -qx -- '--json' <<<"$comp_out" || fallo "completion de fleet debe incluir --json: $comp_out"
grep -qx -- 'HR-DEMO' <<<"$comp_out" || fallo "completion de fleet debe incluir HR-DEMO: $comp_out"

echo "OK fleet"
