#!/bin/bash
# set -x
microk8s enable dns dashboard storage rbac
mk get deployment --namespace=kube-system
while [[ $(mk -n kube-system get pods kubernetes-dashboard-8c67656cd-x6vbn -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
while [[ $(mk -n kube-system get pods dashboard-metrics-scraper-64bcc67c9c-ll6gm -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
while [[ $(mk -n kube-system get pods hostpath-provisioner-85ccc46f96-fxtkt  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
while [[ $(mk -n kube-system get pods hostpath-provisioner-85ccc46f96-fxtkt  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
while [[ $(mk -n kube-system get pods hostpath-provisioner-85ccc46f96-fxtkt  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
cat > dashboard-adminuser.yml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

mk apply -f dashboard-adminuser.yml

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

mk apply -f admin-role-binding.yml
mk config > ~/.kube/config
cat ~/.kube/config
mkdir helm && cd $_
wget https://get.helm.sh/helm-v3.9.3-linux-amd64.tar.gz
tar xvf helm-v3.9.3-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin
rm helm-v3.9.3-linux-amd64.tar.gz
rm -rf linux-amd64
helm repo update && helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-release bitnami/wordpress
