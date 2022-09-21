#!/bin/bash
# set -x
microk8s enable dns dashboard storage rbac
mk get deployment --namespace=kube-system
#while [[ $(mk -n kube-system get pods kubernetes-dashboard -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods dashboard-metrics -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods hostpath-provisioner  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
#while [[ $(mk -n kube-system get pods dashboard-metrics-scraper  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
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
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm repo update && helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-release bitnami/wordpress
