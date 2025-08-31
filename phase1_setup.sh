#!/bin/bash

# phase1_setup.sh
# Purpose: Perform base setup on Debian Trixie VM for monitoring server.
# Assumes: Run as root via SSH; config.sh in /home/monitor/ with exported vars (e.g., export TIMEZONE="America/New_York").
# Workflow: Iterative; Sections 1-2 active with internet check.
# Best practices: Safety options; logging; checks.
# Research: Debian 13 Trixie stable since Jun 2025; apt upgrade -y sufficient/safer; ping for connectivity (8.8.8.8 reliable public DNS, no DNS resolve needed).
# Fixes: Added internet check pre-apt; ping -c 3 -W 5 (3 packets, 5s timeout); exit on fail for safety (apt needs net).
# Idempotency: apt safe to rerun; ping non-destructive.
# Documentation: Inline; update README.md post-success.
# Potential issues: Firewall/DNS may block ping (ufw not yet enabled; assume pfSense allows); if VM bridged, host net affects; fallback to other IP if needed.
# Questions: Confirm ping target (8.8.8.8 ok? Alt: 1.1.1.1)? Vars as expected? LVM/swap details?

# Section 1: Initialize environment
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Must run as root"; exit 1; fi
MONITOR_USER="monitor"  # Hardcoded for bootstrap; overridden by config.sh if differs.
. /etc/os-release  # Source for VERSION_CODENAME.
if [ "${VERSION_CODENAME}" != "trixie" ]; then echo "Not Trixie"; exit 1; fi
source "/home/$MONITOR_USER/config.sh"
LOG_FILE="/var/log/phase1_setup.log"
> "$LOG_FILE"  # Truncate/clear log for this run.
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Phase 1 setup start: $(date)"
echo "Key vars from config.sh:"
echo "MONITOR_USER: $MONITOR_USER"
echo "IN_BAND_IP: $IN_BAND_IP"
echo "GATEWAY: $GATEWAY"
echo "TIMEZONE: $TIMEZONE"
echo "DNS_SERVERS: $DNS_SERVERS"
# Add more as needed, e.g., echo "GRAYLOG_LOG_SIZE: $GRAYLOG_LOG_SIZE"
df -h | grep -E '/var|/srv|/root|/swap' || true  # Log LVM mounts; non-fatal.

# Section 2: System update and upgrade
echo "Checking internet connectivity..."
if ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
    echo "Internet connectivity confirmed."
else
    echo "No internet connectivity."
    echo "Error: No internet access. Check network and try again." >&2
    exit 1
fi
apt update
apt upgrade -y
apt autoremove -y
apt clean

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
