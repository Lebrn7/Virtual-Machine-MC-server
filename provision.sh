#!/usr/bin/env bash
# Provisions an Ubuntu VM as a Minecraft (Java Edition) server.
# Safe to re-run: `vagrant provision` will update/refresh the install.
set -euo pipefail

MC_VERSION="${MC_VERSION:-latest}"
MC_RAM="${MC_RAM:-3G}"
ACCEPT_EULA="${ACCEPT_EULA:-false}"

MC_USER="minecraft"
MC_DIR="/opt/minecraft"
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

log()  { echo -e "\n==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# --- EULA: the user must explicitly accept it ---------------------------------
if [[ "$ACCEPT_EULA" != "true" ]]; then
  fail "You must accept the Minecraft EULA (https://aka.ms/MinecraftEULA).
       Re-run with: ACCEPT_EULA=true vagrant up   (or: ACCEPT_EULA=true vagrant provision)"
fi

# --- Base packages -------------------------------------------------------------
log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq ca-certificates ufw tar cron

# --- Resolve the server version from Mojang's metadata -------------------------
log "Resolving Minecraft version (${MC_VERSION})"
manifest="$(curl -fsSL "$MANIFEST_URL")"
if [[ "$MC_VERSION" == "latest" ]]; then
  MC_VERSION="$(jq -r '.latest.release' <<<"$manifest")"
fi

version_url="$(jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url' <<<"$manifest")"
[[ -n "$version_url" ]] || fail "Minecraft version '$MC_VERSION' not found in Mojang's manifest."

version_json="$(curl -fsSL "$version_url")"
server_url="$(jq -r '.downloads.server.url // empty'  <<<"$version_json")"
server_sha1="$(jq -r '.downloads.server.sha1 // empty' <<<"$version_json")"
java_major="$(jq -r '.javaVersion.majorVersion // 21' <<<"$version_json")"
[[ -n "$server_url" ]] || fail "No server download listed for $MC_VERSION."

# --- Java: install whatever major version this Minecraft release asks for -------
log "Installing Java ${java_major}"
apt-get install -y -qq "openjdk-${java_major}-jre-headless" \
  || fail "Package openjdk-${java_major}-jre-headless is not available on this Ubuntu release.
          Install a matching JDK manually or choose an older MC_VERSION."

# --- Service user and directories ------------------------------------------------
log "Creating user and directories"
id -u "$MC_USER" &>/dev/null || \
  useradd --system --home-dir "$MC_DIR" --shell /usr/sbin/nologin "$MC_USER"
install -d -o "$MC_USER" -g "$MC_USER" -m 750 "$MC_DIR"
install -d -m 750 /var/backups/minecraft

# --- Download and verify server.jar ----------------------------------------------
log "Downloading server.jar for ${MC_VERSION}"
systemctl stop minecraft.service 2>/dev/null || true
jar="$MC_DIR/server.jar"
if [[ ! -f "$jar" ]] || [[ "$(sha1sum "$jar" | cut -d' ' -f1)" != "$server_sha1" ]]; then
  curl -fsSL "$server_url" -o "$jar.tmp"
  [[ "$(sha1sum "$jar.tmp" | cut -d' ' -f1)" == "$server_sha1" ]] || fail "server.jar checksum mismatch."
  mv "$jar.tmp" "$jar"
fi
chown "$MC_USER:$MC_USER" "$jar"
echo "$MC_VERSION" > "$MC_DIR/.mc_version"

# --- Config ----------------------------------------------------------------------
echo "eula=true" > "$MC_DIR/eula.txt"
if [[ ! -f "$MC_DIR/server.properties" ]]; then
  # Minimal seed; the server fills in every other default on first start.
  cat > "$MC_DIR/server.properties" <<'EOF'
motd=Minecraft server running in a VM
view-distance=10
simulation-distance=8
EOF
fi
chown "$MC_USER:$MC_USER" "$MC_DIR/eula.txt" "$MC_DIR/server.properties"

# --- systemd service + console socket --------------------------------------------
log "Installing systemd units"
echo "MC_RAM=${MC_RAM}" > /etc/minecraft.env
install -m 644 /tmp/minecraft.service /etc/systemd/system/minecraft.service
install -m 644 /tmp/minecraft.socket  /etc/systemd/system/minecraft.socket
systemctl daemon-reload
systemctl enable minecraft.socket minecraft.service
systemctl restart minecraft.service

# --- Backups ---------------------------------------------------------------------
log "Installing backup job (daily at 04:00)"
install -m 755 /tmp/backup.sh /usr/local/bin/minecraft-backup
echo "0 4 * * * root /usr/local/bin/minecraft-backup >> /var/log/minecraft-backup.log 2>&1" \
  > /etc/cron.d/minecraft-backup
chmod 644 /etc/cron.d/minecraft-backup

# --- Firewall --------------------------------------------------------------------
log "Configuring firewall"
ufw allow 22/tcp    >/dev/null
ufw allow 25565/tcp >/dev/null
ufw --force enable  >/dev/null

log "Done. Minecraft ${MC_VERSION} is starting (heap: ${MC_RAM})."
echo "Watch it start:  vagrant ssh -c 'sudo journalctl -u minecraft -f'"
