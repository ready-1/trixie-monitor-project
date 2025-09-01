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
- Run this script as sudo
- verify network is up once the script finished

### phase2_setup.sh - Ansible
- run this script as monitor, no sudo
- 

