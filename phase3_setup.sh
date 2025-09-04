#!/bin/bash
# Breadcrumb: [2025-09-03 21:12 EDT | 1743993120] Phase 3 Setup Script for Graylog and Nginx
# Description: Installs and configures Nginx as a reverse proxy and Graylog as a syslog server
# on Debian Trixie for monitoring NETGEAR M4300 switches. Hardcoded paths used per user request.
# Fixes sed error in graylog-server post-install by preconfiguring server.conf.
# Usage: Run as root or with sudo, e.g., `sudo ./phase3_setup.sh`

# Exit on error
set -e

# Define variables
LOG_FILE="/home/monitor/phase3_setup.log"
GRAYLOG_VERSION="6.0"
OPENSEARCH_VERSION="2.11.1"
NGINX_CONF="/etc/nginx/sites-available/graylog"
GRAYLOG_CONF="/etc/graylog/server/server.conf"
REPO_URL="https://packages.graylog2.org/repo/packages/graylog-$GRAYLOG_VERSION-repository_latest.deb"
REPO_KEY="https://packages.graylog2.org/repo/debian/graylog_key.asc"

# Log all output to file and console
exec > >(tee -a "$LOG_FILE") 2>&1
echo "----------------------------------------"
echo "Starting Phase 3 setup at $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------"

# Install required packages
echo "Installing dependencies..."
apt-get update
apt-get install -y curl gnupg apt-transport-https openjdk-21-jre-headless uuid-runtime nginx

# Install OpenSearch
echo "Installing OpenSearch $OPENSEARCH_VERSION..."
wget -4 --timeout=30 -O opensearch.deb "https://artifacts.opensearch.org/releases/bundle/opensearch/$OPENSEARCH_VERSION/opensearch-$OPENSEARCH_VERSION-linux-x64.deb"
dpkg -i opensearch.deb || { echo "OpenSearch installation failed"; exit 1; }
rm opensearch.deb

# Configure OpenSearch
echo "Configuring OpenSearch..."
cat <<EOF >/etc/opensearch/opensearch.yml
cluster.name: graylog
network.host: 127.0.0.1
discovery.type: single-node
plugins.security.disabled: true
EOF
systemctl enable opensearch
systemctl start opensearch

# Install MongoDB
echo "Installing MongoDB..."
wget -4 --timeout=30 -O mongodb.deb "https://repo.mongodb.org/apt/debian/dists/bookworm/mongodb-org/7.0/main/binary-amd64/mongodb-org-server_7.0.14_amd64.deb"
dpkg -i mongodb.deb || { echo "MongoDB installation failed"; exit 1; }
rm mongodb.deb
systemctl enable mongod
systemctl start mongod

# Install Graylog repository
echo "Installing Graylog repository..."
wget -4 --timeout=30 --tries=3 -O graylog-repo.deb "$REPO_URL"
dpkg -i graylog-repo.deb || { echo "Graylog repository installation failed"; exit 1; }
rm graylog-repo.deb
apt-get update

# Preconfigure Graylog server.conf to avoid sed error
echo "Preconfiguring Graylog to avoid sed error..."
mkdir -p /etc/graylog/server
cat <<EOF >"$GRAYLOG_CONF"
mongodb_uri = mongodb://localhost/graylog
is_leader = true
node_id_file = /etc/graylog/server/node-id
password_secret = $(pwgen -N 1 -s 96)
root_password_sha2 = $(echo -n "admin123" | sha256sum | cut -d" " -f1)
root_timezone = UTC
http_bind_address = 127.0.0.1:9000
http_publish_uri = http://$(hostname -I | awk '{print $1}'):9000/
http_enable_cors = true
http_max_header_size = 8192
http_thread_pool_size = 16
EOF
chown graylog:graylog "$GRAYLOG_CONF"
chmod 600 "$GRAYLOG_CONF"

# Install Graylog with workaround for post-install sed error
echo "Installing Graylog $GRAYLOG_VERSION..."
if ! apt-get install -y graylog-server; then
    echo "Warning: Graylog installation encountered errors (likely sed issue). Attempting to fix..."
    dpkg --configure -a  # Re-run configuration to complete setup
    apt-get install -f -y  # Fix any broken dependencies
fi

# Start and enable Graylog
systemctl enable graylog-server
systemctl start graylog-server

# Install and configure Nginx
echo "Configuring Nginx as reverse proxy..."
cat <<EOF >"$NGINX_CONF"
server {
    listen 80;
    server_name $(hostname -f);
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/graylog /etc/nginx/sites-enabled/graylog
nginx -t || { echo "Nginx configuration test failed"; exit 1; }
systemctl enable nginx
systemctl restart nginx

# Verify services
echo "Verifying services..."
for svc in opensearch mongod graylog-server nginx; do
    if ! systemctl is-active --quiet "$svc"; then
        echo "Error: $svc service not running"
        exit 1
    else
        echo "$svc service is running"
    fi
done

# Test Graylog API
echo "Testing Graylog API..."
if curl -s -f http://127.0.0.1:9000/api/system | grep -q "cluster_id"; then
    echo "Graylog API is accessible"
else
    echo "Error: Graylog API not accessible"
    exit 1
fi

echo "----------------------------------------"
echo "Phase 3 setup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo "Access Graylog at http://$(hostname -I | awk '{print $1}'):80 with username 'admin' and password 'admin123'"
echo "Log saved to $LOG_FILE"
echo "----------------------------------------"
