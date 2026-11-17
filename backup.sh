#!/usr/bin/env bash
# Consistent world backup: pause autosaves, flush to disk, archive, resume.
# Installed as /usr/local/bin/minecraft-backup and run daily by cron.
set -euo pipefail

MC_DIR="/opt/minecraft"
WORLD="${WORLD:-world}"
BACKUP_DIR="/var/backups/minecraft"
KEEP="${KEEP:-7}"                 # number of backups to retain
FIFO="/run/minecraft.stdin"

# Write a console command, but never hang if the server isn't reading.
mc_cmd() {
  timeout 5 sh -c 'printf "%s\n" "$1" > "$2"' _ "$1" "$FIFO"
}

[[ -d "$MC_DIR/$WORLD" ]] || { echo "World '$WORLD' not found, nothing to back up."; exit 0; }
mkdir -p "$BACKUP_DIR"

paused=false
if systemctl is-active --quiet minecraft.service; then
  mc_cmd "save-off"
  paused=true
  trap 'mc_cmd "save-on" || true' EXIT
  mc_cmd "save-all flush"
  sleep 15                        # crude wait for the flush; see README "Challenges"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
tar -czf "$BACKUP_DIR/${WORLD}-${stamp}.tar.gz" -C "$MC_DIR" "$WORLD"
echo "$(date -Is) backup written: ${WORLD}-${stamp}.tar.gz (autosave paused: $paused)"

# Prune old backups
ls -1t "$BACKUP_DIR"/${WORLD}-*.tar.gz | tail -n +"$((KEEP + 1))" | xargs -r rm --
