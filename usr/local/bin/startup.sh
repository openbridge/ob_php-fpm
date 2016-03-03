#!/bin/bash

# Add the docker container tag
sed -i 's/ob_tag/'$ob_tag'/g' /etc/monitrc
sed -i 's/ob_mode/'$ob_mode'/g' /etc/monitrc

# Randomly assign tag ID
ob_id=$(shuf -i 10000-20000 -n 1)
sed -i 's/ob_id/'$ob_id'/g' /etc/monitrc

###################
# MONITOR
###################
mkdir -p /ebs/logs/monit
mkdir -p /var/lib/monit
chmod 700 /etc/monitrc

# We will let Monit take care of starting services
/usr/local/bin/monit -I -c /etc/monitrc -l /ebs/logs/monit/monit.log
