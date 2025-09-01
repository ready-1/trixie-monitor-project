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
ansible-vault create ansible/secrets.yaml --vault-id dev@prompt  # Pass; add: ansible_ssh_pass: ""
chmod 600 ansible/secrets.yaml
echo "ansible/secrets.yaml" >> .gitignore

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

# Section 5: Template Inventory (Uncomment later - devlab stubs)
# mkdir -p ansible/inventories templates
# cat <<EOF > templates/inventory.yaml.tmpl
# all:
#   children:
#     switches:
#       hosts:
#         sw-eng-test: {ansible_host: "192.168.99.94", ansible_ssh_pass: "{{ ansible_ssh_pass }}"}  # Devlab stub
#     # Other groups...
# EOF
# envsubst < templates/inventory.yaml.tmpl > ansible/inventories/\$FUSESYSTEM.yaml

# Section 6: Test Ping (Uncomment last)
# ansible-playbook --vault-id dev@prompt -i ansible/inventories/\$FUSESYSTEM.yaml ansible/playbooks/test.yaml
# # test.yaml: - hosts: support_infra tasks: - ansible.builtin.ping:

# Git: git add . && git commit -m "Phase2: Section 1 complete; devlab set"
