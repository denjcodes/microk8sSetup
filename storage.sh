#!/bin/bash
apt update && apt -y upgrade
apt install -y nfs-server net-tools
mkdir /data
cat << EOF >> /etc/exports
/data 192.168.2.47(rw,no_subtree_check,no_root_squash)
EOF
systemctl enable --now nfs-server
exportfs -ar