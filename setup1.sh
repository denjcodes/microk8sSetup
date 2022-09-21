#!/bin/bash
# set -x
yum update -y && yum upgrade -y
yum install -y bash-completion
sudo usermod -a -G microk8s dj
sudo chown -f -R dj ~/.kube
newgrp microk8s
su - dj
rpm --install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf upgrade -y
yum install -y snapd
systemctl enable --now snapd.socket
ln -s /var/lib/snapd/snap /snap
snap wait system seed.loaded
systemctl restart snapd.seeded.service
snap install microk8s --classic --channel=1.25/stable
# alias microkube=microk8s.kubectl >> ~/.bash_profile # add autocomplete
snap alias microk8s.kubectl mk
source <(mk completion bash | sed "s/kubectl/mk/g") >> ~/.bashrc # add autocomplete permanently to your bash shell.
complete -o default -F __start_kubectl microkube
export PATH=$PATH:/usr/local/bin
reboot
