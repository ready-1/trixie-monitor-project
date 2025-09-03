# Project Notes

## Installation Instructions

### Debian Installation
- Do a minimal netinst installation
- Only install core services and the SSH server
- Only install a single network adapter (In Band) at stand up
- leave root password blank
- user is Monitor User
- hostname is monitor-server
- use dhcp for now, phase1_setup.sh will config networking
- verify the network adapter is enp0s5 after installation.  If not, scripts will need to be adjusted.
- after the server stands up, run sync.sh to copy all files.
- verify passwordless login

### Phase1_setup.sh - Network and sysadmin packages
- Run this script with "sudo -E" to provide environment
- verify network is up once the script finished

### phase2_setup.sh - Ansible
- must do "source ./config.sh" before running the script to set up the environment
- run this script as monitor, no sudo
- the only entry needed for the ansible vault at this point is 'ansible_ssh_pass: ""'

### phase3_setup.sh
- must do "source ./config.sh" before running the script to set up the environment
- script must run with"sudo -E' to provide environment
- this script is based on functions allowing single sections to be executed.  a menu displays at start.
- 
