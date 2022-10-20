#!/bin/bash
# set -x
# sudo usermod -a -G microk8s dj
# sudo chown -f -R dj ~/.kube
# su - dj
# newgrp microk8s

yum update -y && yum upgrade -y
yum install -y bash-completion

rpm --import http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
rpm --install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf upgrade -y
yum install -y snapd
systemctl enable --now snapd.socket
ln -s /var/lib/snapd/snap /snap
snap wait system seed.loaded
systemctl restart snapd.seeded.service
snap install microk8s --classic --channel=1.25/stable
alias kubectl="microk8s kubectl"
# alias microkube=microk8s.kubectl >> ~/.bash_profile # add autocomplete
snap alias microk8s.kubectl kubectl
source <(mk completion bash | sed "s/kubectl/mk/g") >> ~/.bashrc # add autocomplete permanently to your bash shell.
complete -o default -F __start_kubectl microkube
export PATH=$PATH:/usr/local/bin

echo Starting wordpress installation

kubectl enable dns dashboard storage rbac helm3 cert-manager

cat > dashboard-adminuser.yml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

kubectl apply -f dashboard-adminuser.yml

cat > admin-role-binding.yml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

kubectl apply -f admin-role-binding.yml

# enable certificate signing
# update cert store with existing cert?
# enable storage?
mk get deployment --namespace=kube-system
# sleep 60
# mk apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

mk config view > ~/.kube/config
cat ~/.kube/config
#while [[ $(mk -n kube-system get pods kubernetes-dashboard -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods dashboard-metrics -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods hostpath-provisioner  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods dashboard-metrics-scraper  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done

mk config view > ~/.kube/config
cat ~/.kube/config
microk8s helm repo add bitnami https://charts.bitnami.com/bitnami && microk8s helm repo update
microk8s helm install my-release bitnami/wordpress
mk get svc --namespace default -w my-release-wordpress



sudo snap install microk8s --classic
sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo ufw default allow routed
alias kubectl="microk8s kubectl"
source ~/.bashrc