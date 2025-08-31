#!/bin/bash
set -euo pipefail
source config.sh  # FUSESYSTEM="devlab"; update/export if missing

# Section 1: Install/Pin Ansible-Core (Active - Run; share ansible --version ~2.19.0)
sudo apt update
if ! dpkg -l | grep -q ansible-core; then
  sudo apt install -y ansible-core
  sudo apt-mark hold ansible-core  # Pin ~2.19.0
fi
ansible --version  # PoL

# Section 2: Install Collections (Uncomment post-Section 1)
# ansible-galaxy collection install community.network community.general -r ansible/requirements.yml
# # requirements.yml: collections: - name: community.network version: ">=5.0.0" - name: community.general

# Section 3: Vault for Creds (Uncomment later)
# mkdir -p ansible
# ansible-vault create ansible/secrets.yaml --vault-id dev@prompt  # Pass; add: ansible_ssh_pass: ""
# chmod 600 ansible/secrets.yaml
# echo "ansible/secrets.yaml" >> .gitignore

# Section 4: Template ansible.cfg (Uncomment later)
# mkdir -p /etc/ansible
# cat <<EOF > /etc/ansible/ansible.cfg
# [defaults]
# inventory = /home/monitor/ansible/inventories/\$FUSESYSTEM.yaml
# host_key_checking = False
# EOF
# chmod 600 /etc/ansible/ansible.cfg

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
