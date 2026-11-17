# Minecraft Server VM

A small, reproducible virtual machine that runs a **Minecraft: Java Edition** server.
One command builds an Ubuntu 24.04 VM with Java, the official server jar (checksum-verified),
a hardened systemd service, daily world backups and a firewall.

Built with [Vagrant](https://www.vagrantup.com/) + [VirtualBox](https://www.virtualbox.org/).

## Quick start

**Requirements:** Vagrant, VirtualBox, and a machine with at least ~5 GB of free RAM.

```bash
git clone <your-repo-url> minecraft-vm
cd minecraft-vm

# You must accept the Minecraft EULA: https://aka.ms/MinecraftEULA
ACCEPT_EULA=true vagrant up
```

Then connect in Minecraft with `localhost:25565` (same machine) or `<your-LAN-IP>:25565` (other devices on your network).

## Configuration

Set these environment variables when running `vagrant up` / `vagrant provision`:

| Variable        | Default  | Meaning                                                        |
|-----------------|----------|----------------------------------------------------------------|
| `ACCEPT_EULA`   | `false`  | Must be `true`, otherwise provisioning stops                   |
| `MC_VERSION`    | `latest` | Minecraft release, e.g. `1.21.4`, or `latest`                  |
| `MC_RAM`        | `3G`     | JVM heap size (`-Xms`/`-Xmx`)                                  |
| `VM_MEMORY_MB`  | `4096`   | RAM given to the VM. Keep ~1 GB above `MC_RAM`                 |
| `VM_CPUS`       | `2`      | CPU cores given to the VM                                      |

Example: `ACCEPT_EULA=true MC_VERSION=1.21.4 MC_RAM=5G VM_MEMORY_MB=6144 vagrant up`

Game settings live in `/opt/minecraft/server.properties` inside the VM.

## Day-to-day usage

```bash
vagrant ssh                                   # shell in the VM
sudo journalctl -u minecraft -f               # live server log
sudo systemctl restart minecraft              # restart the server

# Send console commands (e.g. op yourself, whitelist, say):
echo "op YourName" | sudo tee /run/minecraft.stdin

# Manual backup (also runs daily at 04:00). Archives land in /var/backups/minecraft
sudo minecraft-backup

# Update Minecraft: change the version, then re-provision (world is kept)
ACCEPT_EULA=true MC_VERSION=1.21.5 vagrant provision

vagrant halt        # shut the VM down cleanly
vagrant destroy     # delete the VM (and the world inside it!)
```

## What's in this repo

| File                | Purpose                                                                 |
|---------------------|-------------------------------------------------------------------------|
| `Vagrantfile`       | VM definition: box, resources, port forwarding, provisioning            |
| `provision.sh`      | Installs Java, downloads/verifies the server, sets up service/backups/firewall |
| `minecraft.service` | systemd unit that runs the server as an unprivileged user               |
| `minecraft.socket`  | Creates a FIFO so you can send console commands to the running server   |
| `backup.sh`         | Consistent world backup with retention (installed as `minecraft-backup`)|

## Challenges and design decisions

Running a Minecraft server in a VM is simple on paper, but several things trip people up.

### 1. Memory sizing
Minecraft is memory-hungry, and the JVM needs RAM *beyond* its heap (metaspace, threads, native buffers),
and the OS needs some too. If the VM has 4 GB and you give Java 4 GB, the kernel's OOM killer will
terminate the server. **Rule of thumb:** VM RAM ≈ heap + 1 GB. Also make sure your *host* isn't forced to swap.
We set `-Xms` equal to `-Xmx` to avoid pauses from heap resizing.

### 2. Java version compatibility
Each Minecraft release requires a specific minimum Java version, and this changes over time.
Rather than hardcoding one, `provision.sh` reads the required major version from Mojang's own
version metadata and installs the matching `openjdk-N-jre-headless`. Very new releases may need
a Java version your Ubuntu release doesn't package yet; the script fails loudly with a clear message in that case.

### 3. The EULA
You can't legally run the server without agreeing to Mojang's EULA, so the script refuses to continue
unless you opt in with `ACCEPT_EULA=true`, rather than silently accepting on your behalf.

### 4. Networking (the biggest source of "it doesn't work")
- **NAT + port forwarding (default):** the VM sits behind VirtualBox's NAT; we forward host port 25565 to the guest.
  Works for you and your LAN. If you only want local access, set `host_ip: "127.0.0.1"` in the `Vagrantfile`.
- **Friends over the internet** need a port forward on your *router* (TCP 25565 to your host machine),
  and many ISPs use CGNAT, which makes this impossible. Alternatives are a tunnel service,
  a VPN (e.g. WireGuard/Tailscale), or hosting the VM on a cloud provider.
- **Two firewalls:** the VM's `ufw` and your host's firewall both need to allow 25565.

### 5. Graceful shutdown and world corruption
Killing the JVM mid-save can corrupt chunks. systemd sends `SIGTERM`, which triggers Minecraft's
shutdown hook to save the world; we raise `TimeoutStopSec` to 120s so large worlds can finish.
Always use `vagrant halt` (not "power off" in VirtualBox) so the guest shuts down cleanly.

### 6. Sending console commands to a daemon
A systemd service has no terminal, so there's no console to type into. We use a systemd *socket*
(`minecraft.socket`) that provides a FIFO the service reads as stdin. It's dependency-free.
For richer remote administration, consider enabling RCON in `server.properties` (and protect it with a strong password
and firewall rules, as it is powerful and unencrypted).

### 7. Consistent backups
Copying a world while the server is writing to it can produce a broken archive. The backup script
disables autosave (`save-off`), flushes (`save-all flush`), archives, then re-enables saving.
**Known limitation:** it waits a fixed 15 seconds for the flush rather than confirming completion by reading the
server log. That's fine for small/medium worlds; for large ones, increase the delay or parse the journal
for the "Saved the game" message. Also remember: backups live *inside the VM*. If the VM is destroyed, they go too. Copy them elsewhere
(another disk, cloud storage) for real safety.

### 8. Disk performance
Vagrant's default shared folder is slow and causes world I/O lag, so it's disabled. The world is stored on the VM's own disk.
If you need to move data in or out, use `vagrant scp`/`vagrant ssh` or `scp`.

### 9. Upgrades and world compatibility
Worlds upgrade forward automatically but **can't be downgraded**. Always run `minecraft-backup` before changing `MC_VERSION`.
Plugins/mods (Paper, Fabric, etc.) are version-locked too and aren't handled by this vanilla setup.

### 10. Security
- The server runs as a dedicated, shell-less `minecraft` user with systemd sandboxing (`ProtectSystem`, `NoNewPrivileges`, `PrivateTmp`).
- Only ports 22 and 25565 are open in `ufw`.
- **Enable the whitelist** if the server is reachable beyond your home network:
  `echo "whitelist on" | sudo tee /run/minecraft.stdin` then `echo "whitelist add Name" | sudo tee /run/minecraft.stdin`.
- Don't set `online-mode=false` on a public server, as it disables account authentication.

### 11. Host realities
The server only runs while your host is on, awake and the VM is up. Laptop sleep will drop all players.
Game performance is mostly single-thread-bound; more cores help less than faster ones. If lag appears,
lower `view-distance` / `simulation-distance` in `server.properties` first.

### 12. Apple Silicon / other hypervisors
VirtualBox support on ARM Macs is limited, and the `bento/ubuntu-24.04` box may not match your architecture.
On Apple Silicon use a provider such as Parallels, VMware Fusion or QEMU with an ARM-compatible box and adjust the `Vagrantfile`.
Docker is a lighter alternative to a full VM if you don't specifically need one.

## Troubleshooting

- **Server won't start:** `sudo journalctl -u minecraft -n 100` inside the VM. Look for out-of-memory or Java version errors.
- **Can't connect from another device:** check `host_ip` in the `Vagrantfile`, the host firewall, and that you're using the host's LAN IP, not the VM's.
- **Provisioning says EULA not accepted:** run with `ACCEPT_EULA=true`.

## Disclaimer

This project is not affiliated with Mojang or Microsoft. You are responsible for accepting the
[Minecraft EULA](https://aka.ms/MinecraftEULA). Add a `LICENSE` file of your choice for this repository's own code (e.g. MIT).
