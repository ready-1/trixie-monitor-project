#!/bin/bash

# phase1_setup.sh
# Purpose: Perform base server setup on Debian Trixie VM for monitoring (Phase 1).
# Assumes: Run as root via SSH; config.sh in /home/monitor/ with exported vars (e.g., export TIMEZONE="UTC").
# Workflow: Full script—network config defers to reboot; fixes applied.
# Best practices: Idempotent; logging; checks. ifupdown for networking (Trixie minimal default).
# Research: Trixie static IP via /etc/network/interfaces (ifupdown); sed handles 'allow-hotplug'; reboot applies. Fail2ban needs rsyslog pre-install, backend=systemd config. sshd_config sed handles #; ensure ifupdown installed; networking sed adds auto if missing.
# Fixes: Add rsyslog pre-fail2ban; configure fail2ban sshd backend post-install; sed for sshd_config handles #; ensure ifupdown installed; networking sed adds auto if missing; proper indentation in heredoc for syntax; use separate address/netmask (CIDR supported but explicit for compat).
# Idempotency: Checks skip done parts.
# Documentation: Inline; README.md: Run over SSH, reboot applies IP; troubleshoot fail2ban with journalctl -u fail2ban (jail is 'sshd').
# Potential issues: IP fail—wrong iface name (enp0s5? confirm ip link); DHCP persist—purge isc-dhcp-client. Fail2ban fail—check apt logs (/var/log/apt/history.log), journalctl.
# Questions: /etc/network/interfaces contents? apt install fail2ban errors? journalctl -u fail2ban? Swap (swapon -s)? TIMEZONE to America/New_York? Phase 2 Ansible?

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

# Section 4: Install base utilities
if command -v nvim >/dev/null 2>&1 && command -v fail2ban-client >/dev/null 2>&1; then
    echo "Base utilities already installed; skipping."
else
    apt install -y --no-install-recommends ifupdown rsyslog git neovim htop rsync curl wget net-tools sudo tmux sysstat iotop tcpdump nmap logwatch fail2ban
    usermod -aG sudo "$MONITOR_USER"
    # Post-fail2ban config if installed
    if command -v fail2ban-client >/dev/null 2>&1; then
        mkdir -p /etc/fail2ban/jail.d
        echo "[sshd]" > /etc/fail2ban/jail.d/sshd.local
        echo "enabled = true" >> /etc/fail2ban/jail.d/sshd.local
        echo "backend = systemd" >> /etc/fail2ban/jail.d/sshd.local
        systemctl restart fail2ban
    fi
fi

# Section 5: Configure security basics
if ufw status | grep -q "Status: active"; then
    echo "UFW already enabled; skipping."
else
    apt install -y ufw
    ufw allow OpenSSH
    ufw allow 80/tcp  # For future nginx.
    ufw --force enable
    sed -i '/^#*PasswordAuthentication/s/.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart ssh
fi

# Section 6: Set timezone and locale
timedatectl set-timezone "$TIMEZONE"
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Section 3: Configure networking
if grep -q "iface enp0s5 inet static" /etc/network/interfaces; then
    echo "Static IP already configured; skipping."
    ip addr show enp0s5
    ping -c 3 "$GATEWAY" || echo "Ping failed; check config."
else
    pkill dhclient || true  # Stop any running DHCP; non-fatal.
    apt purge -y isc-dhcp-client dhcpcd5 || true  # Remove DHCP clients if present.
    cp /etc/network/interfaces /etc/network/interfaces.bak
    if ! grep -q "allow-hotplug enp0s5" /etc/network/interfaces && ! grep -q "auto enp0s5" /etc/network/interfaces; then
        echo "allow-hotplug enp0s5" >> /etc/network/interfaces
    fi
    sed -i '/iface enp0s5 inet dhcp/d' /etc/network/interfaces  # Remove old DHCP if exists
    IP_ADDR="${IN_BAND_IP%/*}"
    PREFIX="${IN_BAND_IP#*/}"
    MASK=$(( 0xFFFFFFFF ^ ((1 << (32 - PREFIX)) - 1) ))
    NETMASK=$(printf '%d.%d.%d.%d' $((MASK >> 24 & 255)) $((MASK >> 16 & 255)) $((MASK >> 8 & 255)) $((MASK & 255)))
    cat <<EOF >> /etc/network/interfaces
iface enp0s5 inet static
    address $IP_ADDR
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVERS
EOF
    echo "Network config updated to static IP. Changes apply on reboot."
fi

# Section 7: Final checks and cleanup
echo "Phase 1 setup complete: $(date)"
touch "/home/$MONITOR_USER/[PHASE1_SETUP_SUCCESS_20250831]"
echo "Reboot required to apply network changes. Verify /etc/network/interfaces first."
echo "Post-reboot: Reconnect SSH to $IP_ADDR; test ping/internet."
# Optional auto-reboot: sleep 10; reboot  # Uncomment if console-run.

exit 0
