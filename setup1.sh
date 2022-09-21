#!/bin/bash
# set -x
yum update -y && yum upgrade -y
yum install -y bash-completion
rpm --install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf upgrade -y
yum install -y snapd
systemctl enable --now snapd.socket
ln -s /var/lib/snapd/snap /snap
snap wait system seed.loaded
systemctl restart snapd.seeded.service
snap install microk8s --classic
#alias microkube=microk8s.kubectl >> ~/.bash_profile # add autocomplete
snap alias microk8s.kubectl mk
source <(mk completion bash | sed "s/kubectl/mk/g") >> ~/.bashrc # add autocomplete permanently to your bash shell.
complete -o default -F __start_kubectl microkube
reboot
