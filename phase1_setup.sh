#!/bin/bash

# phase1_setup.sh
# Purpose: Perform base setup on Debian Trixie VM for monitoring server.
# Assumes: Run as root via SSH; config.sh in /home/monitor/ with vars (MONITOR_USER=monitor, IN_BAND_IP, GATEWAY, TIMEZONE, DNS_SERVERS="192.168.99.1 8.8.8.8", etc.).
# Workflow: Iterative; start with Section 1 active.
# Best practices: Safety options; logging; checks.
# Research: Use /etc/os-release for version check (VERSION_CODENAME=trixie in Debian 13; /etc/debian_version=13.0 post-release).
# Fixes: Updated version check to source /etc/os-release; handles stable Trixie (released Aug 2025).
# Idempotency: Minimal in Section 1; expands later.
# Documentation: Inline; update README.md post-success.

# Section 1: Initialize environment
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Must run as root"; exit 1; fi
MONITOR_USER="monitor"  # Hardcoded for bootstrap; overridden by config.sh if differs.
. /etc/os-release  # Source for VERSION_CODENAME.
if [ "${VERSION_CODENAME}" != "trixie" ]; then echo "Not Trixie"; exit 1; fi
source "/home/$MONITOR_USER/config.sh"
LOG_FILE="/var/log/phase1_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Phase 1 setup start: $(date)"
df -h | grep -E '/var|/srv|/root|/swap' || true  # Log LVM mounts; non-fatal.

# # Section 2: System update and upgrade
# apt update
# apt full-upgrade -y
# apt autoremove -y
# apt clean

# # Section 3: Configure networking
# cp /etc/network/interfaces /etc/network/interfaces.bak
# NETMASK=$(echo "$IN_BAND_IP" | awk -F/ '{print $2}' | xargs -I{} sh -c 'printf "255.%s\n" $(for i in $(seq 1 $(({} / 8))); do echo -n "255."; done; rem=$(({} % 8)); if [ $rem -gt 0 ]; then echo -n $((255 - (255 >> $rem))); for i in $(seq $rem 7); do echo -n ".0"; done; else echo ""; fi)' | sed 's/\.$//')
# IP_ADDR=$(echo "$IN_BAND_IP" | cut -d/ -f1)
# cat <<EOF >> /etc/network/interfaces
# 
# auto enp0s5
# iface enp0s5 inet static
#     address $IP_ADDR
#     netmask $NETMASK
#     gateway $GATEWAY
#     dns-nameservers $DNS_SERVERS
# EOF
# ifdown enp0s5 && ifup enp0s5
# ip addr show enp0s5
# ping -c 3 "$GATEWAY"

# # Section 4: Install base utilities
# apt install -y --no-install-recommends git nvim htop rsync curl wget net-tools sudo tmux sysstat iotop tcpdump nmap logwatch fail2ban
# usermod -aG sudo "$MONITOR_USER"

# # Section 5: Configure security basics
# apt install -y ufw
# ufw allow OpenSSH
# ufw allow 80/tcp
# ufw --force enable
# sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# systemctl restart ssh

# # Section 6: Set timezone and locale
# timedatectl set-timezone "$TIMEZONE"
# locale-gen en_US.UTF-8
# update-locale LANG=en_US.UTF-8

# # Section 7: Final checks and cleanup
# echo "Phase 1 setup complete: $(date)"
# touch "/home/$MONITOR_USER/[PHASE1_SETUP_SUCCESS_20250831]"
# echo "Reboot suggested; test connectivity post-reboot."

# exit 0  # Commented; actual exit after active sections.
exit 0
