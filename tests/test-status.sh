#!/usr/bin/env bash
# trio-status: campos merge_sha/merge_danger, notificaciones herdr y fallback a notify-send.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

export TRIO_SHARE_DIR="$tmp/no-share" TRIO_OVERRIDE_DIR="$tmp/no-zt"
unset PJ_TRIO_CONFIG TRIO_LEASE_MINUTES

status_cmd="$aqui/trio-status"
trio_dir="$tmp/trio-28"

# 1. --merge-sha y --merge-danger se escriben en status.json y se preservan.
"$status_cmd" "$trio_dir" hecho cierre --pr "https://github.com/o/r/pull/1" --head "abc1234" \
  --merge-sha "def5678" --merge-danger "two-way / Low"

jq -e '.merge_sha == "def5678" and .merge_danger == "two-way / Low"' "$trio_dir/status.json" >/dev/null \
  || fallo "merge_sha/merge_danger no se escribieron en status.json: $(cat "$trio_dir/status.json")"

"$status_cmd" "$trio_dir" en-curso plan
jq -e '.merge_sha == "def5678" and .merge_danger == "two-way / Low"' "$trio_dir/status.json" >/dev/null \
  || fallo "merge_sha/merge_danger no se preservaron en llamada posterior: $(cat "$trio_dir/status.json")"

# --help documenta ambos flags.
help_out="$("$status_cmd" --help)"
grep -qF -- '--merge-sha' <<<"$help_out" || fallo "--help no documenta --merge-sha"
grep -qF -- '--merge-danger' <<<"$help_out" || fallo "--help no documenta --merge-danger"
for flag in --owner --branch --last-commit --note --heartbeat --lease --worktree; do
  grep -qF -- "$flag" <<<"$help_out" || fallo "--help no documenta $flag"
done

# 1b. Campos de observabilidad (--owner, --branch, --last-commit, --note, --heartbeat, --worktree)
#     se escriben en status.json y se preservan en llamadas posteriores.
trio_obs="$tmp/trio-obs"
"$status_cmd" "$trio_obs" en-curso wk \
  --owner "wk-ravn-trio-225" \
  --branch "issue/225-trio-status-conf" \
  --last-commit "1234567" \
  --note "corriendo tests" \
  --heartbeat "2026-11-24T12:00:00-06:00" \
  --worktree "/z/repos/ravn-trio/225-trio-status-conf"

expected_lease_15="$(date -d "2026-11-24T12:00:00-06:00 + 15 minutes" --iso-8601=seconds)"
jq -e --arg exp_lease "$expected_lease_15" '
  .estado == "en-curso" and .paso == "wk" and
  .owner == "wk-ravn-trio-225" and
  .branch == "issue/225-trio-status-conf" and
  .last_commit == "1234567" and
  .note == "corriendo tests" and
  .heartbeat_at == "2026-11-24T12:00:00-06:00" and
  .lease_expires_at == $exp_lease and
  .worktree == "/z/repos/ravn-trio/225-trio-status-conf"
' "$trio_obs/status.json" >/dev/null \
  || fallo "campos de observabilidad no se escribieron en status.json: $(cat "$trio_obs/status.json")"

"$status_cmd" "$trio_obs" en-curso rv
jq -e --arg exp_lease "$expected_lease_15" '
  .estado == "en-curso" and .paso == "rv" and
  .owner == "wk-ravn-trio-225" and
  .branch == "issue/225-trio-status-conf" and
  .last_commit == "1234567" and
  .note == "corriendo tests" and
  .heartbeat_at == "2026-11-24T12:00:00-06:00" and
  .lease_expires_at == $exp_lease and
  .worktree == "/z/repos/ravn-trio/225-trio-status-conf"
' "$trio_obs/status.json" >/dev/null \
  || fallo "campos de observabilidad no se preservaron en llamada posterior: $(cat "$trio_obs/status.json")"

# 1c. --lease respeta TRIO_LEASE_MINUTES (tanto desde env como desde trio.conf del repo)
mkdir -p "$tmp/pj-lease/.trio"
printf 'TRIO_LEASE_MINUTES=25\n' > "$tmp/pj-lease/.trio/trio.conf"
"$status_cmd" "$tmp/pj-lease/.trio/229" en-curso wk --heartbeat "2026-11-24T12:00:00-06:00" --lease
expected_lease_25="$(date -d "2026-11-24T12:00:00-06:00 + 25 minutes" --iso-8601=seconds)"
jq -e --arg exp_lease "$expected_lease_25" '.lease_expires_at == $exp_lease' "$tmp/pj-lease/.trio/229/status.json" >/dev/null \
  || fallo "--lease no respetó TRIO_LEASE_MINUTES=25 de trio.conf: $(cat "$tmp/pj-lease/.trio/229/status.json")"

TRIO_LEASE_MINUTES=10 "$status_cmd" "$tmp/pj-lease/.trio/229" en-curso wk --lease
lease_ts="$(jq -r '.lease_expires_at' "$tmp/pj-lease/.trio/229/status.json")"
base_ts="$(jq -r '.timestamp' "$tmp/pj-lease/.trio/229/status.json")"
expected_ts="$(date -d "${base_ts} + 10 minutes" --iso-8601=seconds)"
[[ "$lease_ts" == "$expected_ts" ]] \
  || fallo "--lease sin --heartbeat esperaba $expected_ts, dio $lease_ts"

# 2. --notify usa herdr notification show con el --sound según el estado.
mkdir -p "$tmp/bin_ok" "$tmp/bin_fail" "$tmp/bin_noherdr"
cat > "$tmp/bin_ok/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/herdr_ok.log"
EOF
cat > "$tmp/bin_ok/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/notify_ok.log"
EOF
chmod +x "$tmp/bin_ok/herdr" "$tmp/bin_ok/notify-send"

PATH="$tmp/bin_ok:$PATH" "$status_cmd" --notify "$trio_dir" hecho cierre
grep -qE '^notification show trío #trio-28: hecho --body paso cierre --sound done$' "$tmp/herdr_ok.log" \
  || fallo "hecho no invocó herdr con --sound done: $(cat "$tmp/herdr_ok.log")"

PATH="$tmp/bin_ok:$PATH" "$status_cmd" --notify "$trio_dir" needs-roberto merge --error "falló"
grep -qF -- 'notification show trío #trio-28: needs-roberto --body paso merge: falló --sound request' "$tmp/herdr_ok.log" \
  || fallo "needs-roberto no invocó herdr con --sound request: $(cat "$tmp/herdr_ok.log")"

PATH="$tmp/bin_ok:$PATH" "$status_cmd" --notify "$trio_dir" en-curso wk
grep -qF -- 'notification show trío #trio-28: en-curso --body paso wk --sound none' "$tmp/herdr_ok.log" \
  || fallo "en-curso no invocó herdr con --sound none: $(cat "$tmp/herdr_ok.log")"

[[ ! -e "$tmp/notify_ok.log" ]] || fallo "invocó notify-send cuando herdr funcionó"

# 3. Fallback a notify-send cuando herdr falla.
cat > "$tmp/bin_fail/herdr" <<EOF
#!/usr/bin/env bash
exit 1
EOF
cat > "$tmp/bin_fail/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/notify_fail.log"
EOF
chmod +x "$tmp/bin_fail/herdr" "$tmp/bin_fail/notify-send"

PATH="$tmp/bin_fail:$PATH" "$status_cmd" --notify "$trio_dir" needs-roberto rv --error "bloqueo" 2>/dev/null
grep -qF -- '-u critical trío #trio-28: needs-roberto paso rv: bloqueo' "$tmp/notify_fail.log" \
  || fallo "no hizo fallback a notify-send cuando herdr falló"

# 4. Fallback a notify-send cuando herdr no está en el PATH.
for cmd in bash sh dirname basename realpath mkdir cat date jq tail tput; do
  if bin_path="$(command -v "$cmd" 2>/dev/null)"; then
    ln -sf "$bin_path" "$tmp/bin_noherdr/$cmd"
  fi
done
cat > "$tmp/bin_noherdr/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/notify_noherdr.log"
EOF
chmod +x "$tmp/bin_noherdr/notify-send"

PATH="$tmp/bin_noherdr" "$status_cmd" --notify "$trio_dir" hecho cierre
grep -qF -- '-u critical trío #trio-28: hecho paso cierre' "$tmp/notify_noherdr.log" \
  || fallo "no hizo fallback a notify-send sin herdr en PATH"

# 5. --dry-run con --notify muestra el comando de notificación que se ejecutaría.
dry_herdr="$(PATH="$tmp/bin_ok:$PATH" "$status_cmd" --dry-run --notify "$trio_dir" hecho cierre)"
grep -qF -- '[dry-run] herdr notification show "trío #trio-28: hecho" --body "paso cierre" --sound "done"' <<<"$dry_herdr" \
  || fallo "--dry-run --notify con herdr no mostró el comando esperado: $dry_herdr"

dry_noherdr="$(PATH="$tmp/bin_noherdr" "$status_cmd" --dry-run --notify "$trio_dir" hecho cierre)"
grep -qF -- '[dry-run] notify-send -u critical "trío #trio-28: hecho" "paso cierre"' <<<"$dry_noherdr" \
  || fallo "--dry-run --notify sin herdr no mostró notify-send: $dry_noherdr"

echo "OK trio-status"
