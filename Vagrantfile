# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Minecraft server VM.
# Configure with environment variables, e.g.:
#   ACCEPT_EULA=true MC_VERSION=latest MC_RAM=3G vagrant up

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "minecraft"

  # The default shared folder hurts disk performance and we don't need it.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Forward the Minecraft port. host_ip 0.0.0.0 exposes it to your LAN;
  # change to "127.0.0.1" to keep the server reachable from this machine only.
  config.vm.network "forwarded_port",
    guest: 25565, host: 25565, protocol: "tcp", host_ip: "0.0.0.0"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "minecraft-server"
    # VM RAM must be comfortably larger than the JVM heap (MC_RAM).
    vb.memory = ENV.fetch("VM_MEMORY_MB", "4096").to_i
    vb.cpus   = ENV.fetch("VM_CPUS", "2").to_i
  end

  # Upload the files the provisioning script installs.
  config.vm.provision "file", source: "minecraft.service", destination: "/tmp/minecraft.service"
  config.vm.provision "file", source: "minecraft.socket",  destination: "/tmp/minecraft.socket"
  config.vm.provision "file", source: "backup.sh",         destination: "/tmp/backup.sh"

  config.vm.provision "shell", path: "provision.sh", env: {
    "ACCEPT_EULA" => ENV.fetch("ACCEPT_EULA", "false"),
    "MC_VERSION"  => ENV.fetch("MC_VERSION", "latest"),
    "MC_RAM"      => ENV.fetch("MC_RAM", "3G"),
  }
end
