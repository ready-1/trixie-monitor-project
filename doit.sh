#!/bin/bash

# a little script to run the current installation script
# because I am lazy and don't want to type
# invoke with: sudoit.sh <phase number> <step to run>

# setup the environment just in case the script doesn't
source /home/monitor/config.sh
source /home/monitor/load_secrets.sh
clear

# give a little info
echo -e "executing... \n Command: bash /home/monitor/phase${1}_setup.sh $2"
# execute the script as monitor user 
bash /home/monitor/phase${1}_setup.sh $2

