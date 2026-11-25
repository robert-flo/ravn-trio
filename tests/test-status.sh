#!/usr/bin/env bash
# trio-status: campos merge_sha/merge_danger, notificaciones herdr y fallback a notify-send.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fallo() { echo "FALLO: $*" >&2; exit 1; }

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
for flag in --owner --branch --last-commit --note --heartbeat --worktree; do
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

jq -e '
  .estado == "en-curso" and .paso == "wk" and
  .owner == "wk-ravn-trio-225" and
  .branch == "issue/225-trio-status-conf" and
  .last_commit == "1234567" and
  .note == "corriendo tests" and
  .heartbeat_at == "2026-11-24T12:00:00-06:00" and
  .worktree == "/z/repos/ravn-trio/225-trio-status-conf"
' "$trio_obs/status.json" >/dev/null \
  || fallo "campos de observabilidad no se escribieron en status.json: $(cat "$trio_obs/status.json")"

"$status_cmd" "$trio_obs" en-curso rv
jq -e '
  .estado == "en-curso" and .paso == "rv" and
  .owner == "wk-ravn-trio-225" and
  .branch == "issue/225-trio-status-conf" and
  .last_commit == "1234567" and
  .note == "corriendo tests" and
  .heartbeat_at == "2026-11-24T12:00:00-06:00" and
  .worktree == "/z/repos/ravn-trio/225-trio-status-conf"
' "$trio_obs/status.json" >/dev/null \
  || fallo "campos de observabilidad no se preservaron en llamada posterior: $(cat "$trio_obs/status.json")"

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
