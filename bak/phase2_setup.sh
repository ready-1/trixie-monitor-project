#!/bin/bash
set -euo pipefail

# Persistence Fix: Use full path for user home (idempotent; avoids sudo HOME=/root issues)
USER_HOME="/home/monitor"
if ! grep -q "source $USER_HOME/config.sh" $USER_HOME/.bashrc; then
  echo "source $USER_HOME/config.sh" >> $USER_HOME/.bashrc
fi
source $USER_HOME/.bashrc  # Apply; loads exported FUSESYSTEM="devlab", etc.
echo $FUSESYSTEM  # Verify in output: "devlab"

# Section 1: Install/Pin Ansible-Core (Active - Run; share ansible --version ~2.19.0)
sudo apt update
if ! dpkg -l | grep -q ansible-core; then
  sudo apt install -y ansible-core
  sudo apt-mark hold ansible-core  # Pin ~2.19.0
fi
ansible --version  # PoL

# Section 2: Install Collections (Uncomment post-Section 1)
mkdir -p ansible
cat <<EOF > ansible/requirements.yml
collections:
  - name: community.network
    version: ">=5.0.0"  # Pin for replicability; assume CLI fallback compat issues
  - name: community.general
EOF
ansible-galaxy collection install -r ansible/requirements.yml  # Install; verbose: add -vvv if errors
ansible-galaxy collection list  # PoL: Verify installed versions
# requirements.yml: collections: - name: community.network version: ">=5.0.0" - name: community.general

# Section 3: Vault for Creds (Uncomment later)
echo "ansible/secrets.yaml" >> .gitignore

# create stubs for snmp and ansible_ssh
TEMP_FILE=$(mktemp)
echo "snmp_user: monitor  # Read-only user" >> $TEMP_FILE
echo "snmp_auth_proto: sha512  # Auth protocol" >> $TEMP_FILE
echo "snmp_auth_pass: \"$MONITOR_PASS\"  # Vaulted; 8-32 chars" >> $TEMP_FILE
echo "snmp_priv_proto: aes128  # Priv protocol" >> $TEMP_FILE
echo "snmp_priv_pass: \"$MONITOR_PASS\"  # Vaulted; 8-32 chars" >> $TEMP_FILE
echo "ansible_ssh_pass: \"\"" >> $TEMP_FILE
ansible-vault encrypt $TEMP_FILE --vault-id dev@prompt  # Encrypt temp (prompt pw)
mv $TEMP_FILE ansible/secrets.yaml  # Overwrite original
rm -f $TEMP_FILE  # Cleanup
chmod 600 ansible/secrets.yaml



# Section 4: Template ansible.cfg (Uncomment later)
USER_HOME="/home/monitor"
if [ ! -d "/etc/ansible" ]; then
  sudo mkdir -p /etc/ansible  # Sudo for perms; idempotent check
fi
sudo bash -c "cat <<EOF > /etc/ansible/ansible.cfg
[defaults]
inventory = $USER_HOME/ansible/inventories/$FUSESYSTEM.yaml
host_key_checking = False  # Devlab initial; assume M4300-52G-PoE+ 12.0.19.6 quirks
EOF"
sudo chmod 644 /etc/ansible/ansible.cfg # World-readable (secure for config; best practice)


# Section 5: Template Inventory/Subnets/Vars (Active - Rerun for fix; then Section 6)
mkdir -p ansible/{inventories,group_vars/$FUSESYSTEM,group_vars/all,templates}  # User-owned
cat <<EOF > ansible/templates/inventory.yaml.tmpl  # Fixed: Added 'hosts:' under groups per docs
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
if [ -f "ansible/templates/inventory.yaml.tmpl" ]; then
  envsubst < ansible/templates/inventory.yaml.tmpl > ansible/inventories/$FUSESYSTEM.yaml
else
  echo "Error: templates/inventory.yaml.tmpl not found (rerun cat block)"
  exit 1
fi
# Stub group_vars/$FUSESYSTEM/subnets.yaml (short; no fix needed)
cat <<EOF > ansible/group_vars/$FUSESYSTEM/subnets.yaml
in_band: "192.168.99.0/24"  # Devlab
oob: "172.31.29.0/24"  # Override for green
transit: "172.31.0.4/30"
EOF
# Stub group_vars/all/port_profiles.yaml (short; no fix needed)
cat <<EOF > ansible/group_vars/all/port_profiles.yaml
port_profiles:
  default_data:
    mode: access
    vlan: 1  # Placeholder
    description: "Standard Data Port"
    spanning_tree: portfast
    multicast: igmp_snooping
EOF
yamllint ansible/inventories/$FUSESYSTEM.yaml  # Validate; expect clean

# Section 6: Test Ping (Uncomment after Section 5 rerun)
mkdir -p ansible/playbooks
cat <<EOF > ansible/playbooks/test.yaml
- hosts: support_infra
  gather_facts: false  # Fix facts error for local host
  tasks:
    - ansible.builtin.ping:
EOF
ansible-playbook --vault-id dev@prompt ansible/playbooks/test.yaml  # Local PoL; expect success

# Git: git add . && git commit -m "Phase2: Section 1 complete; devlab set"
