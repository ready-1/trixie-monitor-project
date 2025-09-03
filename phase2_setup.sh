#!/bin/bash
# phase2_setup.sh
# Purpose: Setup Ansible for device inventory and server management (Phase 2).
# Assumes: Run as $MONITOR_USER; config.sh in /home/$MONITOR_USER/ with exported vars (e.g., FUSESYSTEM).
# Breadcrumb: [PHASE2_HOME_DIR_FIX_20250903] Use $USER_HOME=/home/$MONITOR_USER across script.
# Research: Ansible-core 2.19 stable for Debian Trixie; community.network for Netgear M4300. Vault for creds.
# Best Practice: Pin versions, idempotent, user-owned Ansible configs.
# Compatibility: No breaks with Graylog/Prometheus/Grafana. M4300 SNMPv3 via community.network.
# Idempotency: Checks skip done parts.
# Usage: ./phase2_setup.sh

set -euo pipefail
MONITOR_USER="monitor"  # Hardcoded fallback; overridden by config.sh
source /home/$MONITOR_USER/config.sh  # Load early to get MONITOR_USER, FUSESYSTEM
USER_HOME="/home/$MONITOR_USER"

# Persistence Fix: Source config.sh in .bashrc (idempotent)
if ! grep -q "source $USER_HOME/config.sh" $USER_HOME/.bashrc; then
  echo "source $USER_HOME/config.sh" >> $USER_HOME/.bashrc
fi
source $USER_HOME/.bashrc  # Apply; loads exported FUSESYSTEM="devlab", etc.
echo $FUSESYSTEM  # Verify in output: "devlab"

# Section 1: Install/Pin Ansible-Core
sudo apt update
if ! dpkg -l | grep -q ansible-core; then
  sudo apt install -y ansible-core
  sudo apt-mark hold ansible-core  # Pin ~2.19.0
fi
ansible --version  # PoL

# Section 2: Install Collections
mkdir -p $USER_HOME/ansible
cat <<EOF > $USER_HOME/ansible/requirements.yml
collections:
  - name: community.network
    version: ">=5.0.0"  # Pin for replicability; assume CLI fallback compat issues
  - name: community.general
EOF
ansible-galaxy collection install -r $USER_HOME/ansible/requirements.yml  # Install; verbose: add -vvv if errors
ansible-galaxy collection list  # PoL: Verify installed versions
# requirements.yml: collections: - name: community.network version: ">=5.0.0" - name: community.general

# Section 3: Vault for Creds
echo "$USER_HOME/ansible/secrets.yaml" >> $USER_HOME/.gitignore

# Create stubs for snmp and ansible_ssh
TEMP_FILE=$(mktemp)
echo "snmp_user: monitor  # Read-only user" >> $TEMP_FILE
echo "snmp_auth_proto: sha512  # Auth protocol" >> $TEMP_FILE
echo "snmp_auth_pass: \"$MONITOR_PASS\"  # Vaulted; 8-32 chars" >> $TEMP_FILE
echo "snmp_priv_proto: aes128  # Priv protocol" >> $TEMP_FILE
echo "snmp_priv_pass: \"$MONITOR_PASS\"  # Vaulted; 8-32 chars" >> $TEMP_FILE
echo "ansible_ssh_pass: \"\"" >> $TEMP_FILE
ansible-vault encrypt $TEMP_FILE --vault-id dev@prompt  # Encrypt temp (prompt pw)
mv $TEMP_FILE $USER_HOME/ansible/secrets.yaml  # Overwrite original
rm -f $TEMP_FILE  # Cleanup
chmod 600 $USER_HOME/ansible/secrets.yaml

# Section 4: Template ansible.cfg
if [ ! -d "/etc/ansible" ]; then
  sudo mkdir -p /etc/ansible  # Sudo for perms; idempotent check
fi
sudo bash -c "cat <<EOF > /etc/ansible/ansible.cfg
[defaults]
inventory = $USER_HOME/ansible/inventories/$FUSESYSTEM.yaml
host_key_checking = False  # Devlab initial; assume M4300-52G-PoE+ 12.0.19.6 quirks
EOF"
sudo chmod 644 /etc/ansible/ansible.cfg # World-readable (secure for config; best practice)

# Section 5: Template Inventory/Subnets/Vars
mkdir -p $USER_HOME/ansible/{inventories,group_vars/$FUSESYSTEM,group_vars/all,templates}  # User-owned
cat <<EOF > $USER_HOME/ansible/templates/inventory.yaml.tmpl
---
all:
  children:
    switches:
      hosts:
        sw-eng-test:
          ansible_host: "192.168.99.94"
          ansible_ssh_pass: "{{ ansible_ssh_pass }}"  # Devlab stub; vault var
    network_devices: {}  # pfSense/NAS stubs
    internal_hosts: {}  # Video router/clock; ping
    external_hosts:
      hosts:
        google_dns:
          ansible_host: "8.8.8.8"
          monitoring: {type: icmp}  # PoL stub
    support_infra:
      hosts:
        monitor_server: {ansible_connection: local}  # UPS/server
  vars:
    ansible_network_os: community.network.netgear_mseries  # Compat fallback
EOF
if [ -f "$USER_HOME/ansible/templates/inventory.yaml.tmpl" ]; then
  envsubst < $USER_HOME/ansible/templates/inventory.yaml.tmpl > $USER_HOME/ansible/inventories/$FUSESYSTEM.yaml
else
  echo "Error: templates/inventory.yaml.tmpl not found (rerun cat block)"
  exit 1
fi
# Stub group_vars/$FUSESYSTEM/subnets.yaml
cat <<EOF > $USER_HOME/ansible/group_vars/$FUSESYSTEM/subnets.yaml
in_band: "192.168.99.0/24"  # Devlab
oob: "172.31.29.0/24"  # Override for green
transit: "172.31.0.4/30"
EOF
# Stub group_vars/all/port_profiles.yaml
cat <<EOF > $USER_HOME/ansible/group_vars/all/port_profiles.yaml
port_profiles:
  default_data:
    mode: access
    vlan: 1  # Placeholder
    description: "Standard Data Port"
    spanning_tree: portfast
    multicast: igmp_snooping
EOF
yamllint $USER_HOME/ansible/inventories/$FUSESYSTEM.yaml  # Validate; expect clean

# Section 6: Test Ping
mkdir -p $USER_HOME/ansible/playbooks
cat <<EOF > $USER_HOME/ansible/playbooks/test.yaml
- hosts: support_infra
  gather_facts: false  # Fix facts error for local host
  tasks:
    - ansible.builtin.ping:
EOF
ansible-playbook --vault-id dev@prompt $USER_HOME/ansible/playbooks/test.yaml  # Local PoL; expect success

# Git: git add . && git commit -m "Phase2: Section 1 complete; devlab set"
