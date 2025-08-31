#!/bin/bash
# phase1_setup.sh: Configures Debian 13.0.0 (Trixie) for Phase 1 monitoring
# Purpose: Set up networking, packages, Tailscale, Cockpit, TFTP, UFW, LVM, logrotate
# Usage: sudo ./phase1_setup.sh
# Breadcrumb: [PHASE1_SETUP_SH_20250830] Updated for Trixie, single NIC, config.sh
# Requirements: Debian 13.0.0, root access, x86_64, config.sh in same dir
# Notes: Idempotent, sources config.sh, optional packages

set -e

# Source config.sh
if [ ! -f ./config.sh ]; then
    echo "Error: config.sh not found in current directory."
    exit 1
fi
. ./config.sh

# Validate required variables
if [ -z "$IN_BAND_IP" ] || [ -z "$GATEWAY" ] || [ -z "$MONITOR_USER" ]; then
    echo "Error: Missing required variables in config.sh (IN_BAND_IP, GATEWAY, MONITOR_USER)."
    exit 1
fi

# Auto-detect NIC (single in-band)
IN_BAND_IF=$(ip link | grep -E '^[0-9]+: (eth[0-9]|enp[0-9]s[0-9])' | head -n1 | awk '{print $2}' | tr -d ':')
if [ -z "$IN_BAND_IF" ]; then
    echo "Error: Could not detect NIC. Check 'ip link'."
    exit 1
fi
echo "Detected NIC: in-band=$IN_BAND_IF"

# Configure networking (skip if IP matches)
CURRENT_IN_BAND_IP=$(ip addr show $IN_BAND_IF | grep -o 'inet [0-9.]\+/[0-9]\+' | awk '{print $2}' || true)
if [ "$CURRENT_IN_BAND_IP" = "$IN_BAND_IP" ]; then
    echo "Network IP already set correctly. Skipping networking changes."
else
    cat <<EOF > /etc/network/interfaces
# The loopback network interface
auto lo
iface lo inet loopback

# In-band
auto $IN_BAND_IF
iface $IN_BAND_IF inet static
    address ${IN_BAND_IP%/*}
    netmask ${IN_BAND_IP#*/}
    gateway $GATEWAY
    dns-nameservers $GATEWAY 8.8.8.8
EOF
    if ip link show wlan0 &>/dev/null; then
        echo "iface wlan0 inet manual" >> /etc/network/interfaces
    fi
    systemctl restart networking
fi

# Update repositories
cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
apt update

# Packages (optional firmware/snmp)
apt install -y vim curl wget net-tools htop chrony ufw snmp tcpdump sysstat arp-scan systemd-resolved tftpd-hpa cockpit logrotate netcat-traditional
apt install -y firmware-linux-nonfree-misc || echo "Warning: firmware-linux-nonfree-misc not available, continuing."
apt install -y snmp-mibs-downloader || echo "Warning: snmp-mibs-downloader not available, skipping."

# Authentication
if ! id $MONITOR_USER &>/dev/null; then
    useradd -m -s /bin/bash $MONITOR_USER
    echo "$MONITOR_USER:$MONITOR_PASS" | chpasswd
fi
su - $MONITOR_USER -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
if [ ! -f /home/$MONITOR_USER/.ssh/id_ed25519 ]; then
    su - $MONITOR_USER -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C '$MONITOR_USER@server'"
fi
if [ -n "$PUBLIC_SSH_KEY" ]; then
    echo "$PUBLIC_SSH_KEY" >> /home/$MONITOR_USER/.ssh/authorized_keys
    chmod 600 /home/$MONITOR_USER/.ssh/authorized_keys
    chown $MONITOR_USER:$MONITOR_USER /home/$MONITOR_USER/.ssh/authorized_keys
fi
usermod -aG cockpit $MONITOR_USER

# Tailscale
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian trixie main" | tee /etc/apt/sources.list.d/tailscale.list
apt update && apt install -y tailscale
systemctl enable --now systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --auth-key=$TAILSCALE_AUTHKEY --advertise-routes=$TAILSCALE_SUBNET --accept-dns=false
else
    echo "Run 'tailscale up --advertise-routes=$TAILSCALE_SUBNET --accept-dns=false' manually."
fi

# TFTP
mkdir -p /srv/tftp
chown -R tftp:tftp /srv/tftp
sed -i 's|^TFTP_DIRECTORY=.*|TFTP_DIRECTORY="/srv/tftp"|' /etc/default/tftpd-hpa
sed -i 's|^TFTP_OPTIONS=.*|TFTP_OPTIONS="--secure"|' /etc/default/tftpd-hpa
systemctl restart tftpd-hpa

# Cockpit
systemctl enable --now cockpit.socket

# Firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 161/udp
ufw allow 162/udp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 9000/tcp
ufw allow 41641/udp
ufw allow 3478/udp
ufw allow 443/tcp
ufw allow 9090/tcp
ufw enable -y

# LVM (adjusts /var/log/graylog if needed)
if ! grep -q "/var/log/graylog" /etc/fstab; then
    if ! lvs | grep -q graylog_logs; then
        DISK=$(lsblk -dno NAME | grep -E 'sda|nvme0n1' | head -n1)
        if [ -z "$DISK" ]; then
            echo "Error: No suitable disk (sda/nvme0n1) found for LVM."
            exit 1
        fi
        if ! pvs | grep -q "/dev/$DISK"; then
            pvcreate /dev/$DISK || true
        fi
        vgcreate vg0 /dev/$DISK || true
        lvcreate -L $GRAYLOG_LOG_SIZE -n graylog_logs vg0 || true
        mkfs.ext4 /dev/vg0/graylog_logs
        mkdir -p /var/log/graylog
        echo "/dev/mapper/vg0-graylog_logs /var/log/graylog ext4 defaults 0 2" >> /etc/fstab
        mount /var/log/graylog
    fi
fi

# Logrotate
cat <<EOF > /etc/logrotate.d/system-logs
/var/log/syslog /var/log/messages {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        invoke-rc.d rsyslog rotate > /dev/null
    endscript
}
EOF

echo "Phase 1 setup complete. Reboot recommended."
