#!/bin/bash
set -x
if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit 1; fi

sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo snap install microk8s --classic
microk8s status --wait-ready
sudo micrk8s
sudo snap alias microk8s.kubectl kubectl
kubectl enable dns dashboard storage rbac helm3 cert-manager ingress
#export alias kubectl="microk8s kubectl"
#source .bashrc
#reboot

kubectl version --client

sudo snap install helm --classic
source /usr/share/bash-completion/bash_completion
echo 'source <(kubectl completion bash)' >>~/.bashrc
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert.sha256"
echo "$(cat kubectl-convert.sha256) kubectl-convert" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
kubectl config view --raw > ~/.kube/config
chmod g-r ~/.kube/config
chmod o-r ~/.kube/config

# kubeadm init

helm upgrade --install ingress-nginx ingress-nginx \
   --repo https://kubernetes.github.io/ingress-nginx \
   --namespace ingress-nginx --create-namespace

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
   cert-manager jetstack/cert-manager \
   --namespace cert-manager \
   --create-namespace \
   --version v1.7.1 \
   --set installCRDs=true

tee -a kustomization.yaml << EOF
 secretGenerator:
      - name: mysql-password
        literals:
        - password=Mysql.Root2022@
      - name: mysql-user
        literals:
        - username=userwp
      - name: mysql-user-password
        literals:
        - passworduser=Mysql.User2022@
      - name: mysql-database
        literals:
        - database=multitenant_wp
EOF

kubectl apply -k .

tee -a  mysql-pv-volume.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
spec:
  storageClassName: do-block-storage
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    # path: //NFS/Data/WP/var/lib/mysql
    path: "/var/lib/mysql"
EOF

tee -a  mysql-pv-claim.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
spec:
  storageClassName: do-block-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF

kubectl apply -f mysql-pv-volume.yaml
kubectl apply -f mysql-pv-claim.yaml

kubectl get pv

tee -a  wordpress-pv-volume.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: wordpress-pv
spec:
  storageClassName: do-block-storage
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    # path: //NFS/Data/WP/www
    path: "/var/www"
EOF

tee --a  wordpress-pv-claim.yaml  << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pv-claim
spec:
  storageClassName: do-block-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
EOF

kubectl apply -f wordpress-pv-volume.yaml
kubectl apply -f wordpress-pv-claim.yaml
kubectl get pv

kubectl describe secret | grep mysql- >> setupValues.txt
echo "Modifing the values for mysql-\n"
# create python script to replace values from describe secret

tee -a mysql-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql-wp
spec:
  ports:
    - port: 3306
  selector:
    app: wordpress
    tier: mysql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-wp
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - image: mysql:latest
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-password-7fbhb7d925
              key: password
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-user-4t5mcf8dkm
              key: username
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-user-password-9g9h872dt6
              key: passworduser
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: mysql-database-4f74mgddt5
              key: database
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pv-claim
EOF

tee -a wordpress-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: web
  type: LoadBalancer

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: web
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: web
    spec:
      containers:
      - image: wordpress:php8.1-apache
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql-wp:3306
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-user-password-9m7k5b4k2m
              key: passworduser
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: mysql-user-4t5mcf8dkm
              key: username
        - name: WORDPRESS_DB_NAME
          valueFrom:
            secretKeyRef:
              name: mysql-database-4f74mgddt5
              key: database
        ports:
        - containerPort: 80
          name: wordpress
        volumeMounts:
        - name: persistent-storage
          mountPath: /var/www/html
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: wordpress-pv-claim
EOF

tee -a modifyValues.py << EOF
import os
import sys
import fileinput

with open('setupValues.txt', 'r') as file:
	fileData = file.readlines()

setupIndex = {}
for line in fileData:
	key = "-".join("-".join(line.split("         ")[1:]).split("-")[:-1])
	value = line.split("-")[-1].strip()
	setupIndex[key] = value
files = ['mysql-service.yaml', 'wordpress-service.yaml']

for yamlFile in files:
	lines = []
	print(yamlFile)
	with open(yamlFile, 'r') as file:
		fileData = file.readlines()

		for line in fileData:
			line2 = ""
			for key in setupIndex.keys():
				if key in line and (("password") in key and ("password") in line):
					oldValue = str(line.split("-")[-1]).strip()
					newValue = setupIndex[key]
					if oldValue != newValue:
						# print(line.strip(), line2.strip(), len(line2))
						line2 = line.replace(oldValue, newValue)
						# print(line.strip(), line2.strip(), len(line2))


			if len(line2): lines.append(line2)
			else: lines.append(line)

#	print(fileData)
# 	print(lines)

	with open(yamlFile, 'w') as file:
		for line in lines: file.write(line)
EOF

python3 modifyValues.py

kubectl apply -f wordpress-service.yaml
kubectl apply -f mysql-service.yaml

tee -a wp_production_issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: wp-prod-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: d2j666@hotmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl apply -f wp_production_issuer.yaml

tee -a  wordpress-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wordpress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "wp-prod-issuer"
spec:
  rules:
  - host: divertmentalhealth.com
    http:
     paths:
     - path: "/"
       pathType: Prefix
       backend:
         service:
           name: wordpress
           port:
             number: 80
  tls:
  - hosts:
    - divertmentalhealth.com
    secretName: wordpress-tls
EOF
kubectl apply -f wordpress-ingress.yaml

microk8s enable dns dashboard storage rbac helm3 # cert-manager

cat > dashboard-adminuser.yml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

tee -a > admin-role-binding.yml << EOF
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

tee -a > admin.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-admin
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: k8s-admin
rules:
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - list
      - get
      - delete
      - create
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: k8s-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-admin
subjects:
- kind: ServiceAccount
  name: k8s-admin
  namespace: default
---
apiVersion: v1
kind: Pod
metadata:
  name: k8s-admin
spec:
  serviceAccountName: k8s-admin
  containers:
  - image: nabsul/k8s-admin:v002
    name: kube
EOF

kubectl apply -f dashboard-adminuser.yml
kubectl apply -f admin-role-binding.yml

token=$(kubectl -n kube-system get secret | grep default-token | cut -d " " -f1)
kubectl -n kube-system describe secret $token

## Certification Management
#snap install --classic certbot
#ln -s /snap/bin/certbot /usr/bin/certbot
#
#tee -a > acme-challenge.yaml << EOF
#- path: /.well-known/acme-challenge
#  pathType: Prefix
#  backend:
#    serviceName: acme-challenge
#    servicePort: 80
#EOF

#Staging only:
# swapoff -a
# lsmod | grep br_netfilter
# modprobe br_netfilter
# lsmod | grep br_netfilter

# cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
# br_netfilter
# EOF


# cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
# net.bridge.bridge-nf-call-ip6tables = 1
# net.bridge.bridge-nf-call-iptables = 1
# EOF

# sysctl --system
# dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
# dnf install docker-ce -y
# systemctl enable --now docker
# systemctl status docker

#cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
# [kubernetes]
# name=Kubernetes
# baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
# enabled=1
# gpgcheck=1
# repo_gpgcheck=1
# gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
# exclude=kubelet kubeadm kubectl
# EOF

# dnf -y install kubeadm kubelet kubectl
# systemctl enable --now kubelet
# systemctl status kubelet

# tee -a > kubeadm-config.yaml << EOF
# kind: ClusterConfiguration
# apiVersion: kubeadm.k8s.io/v1beta3
# kubernetesVersion: v1.23.4
# ---
# kind: KubeletConfiguration
# apiVersion: kubelet.config.k8s.io/v1beta1
# cgroupDriver: cgroupfs
# EOF

# kubeadm init --config kubeadm-config.yaml

# kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
# kubectl get pods --all-namespaces
# kubect get nodes
# kubectl get all

# Check for existin tokens
# kubeadm token list
# Create new tokens
# kubeadm token create

# kubeadm join k8sMaster --token <token>
#    --discovery-token-ca-cert-hash sha256:fe3a21999a46437b7d3127d39aabac0963fef1305f2dbbc70e59befd1deca805\

# kubectl get nodes
# kubectl describe node k8sSlave1

# kubectl create deployment nginx --image=nginx
# kubectl create service nodeport nginx --tcp=80:80
# kubectl scale deployment.apps/nginx --replicas=2
# curl k8sSlave1:<nodeport>

kubectl get all --all-namespaces

sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo usermod -a -G microk8s k8s
sudo chown -f -R k8s ~/.kube
newgrp microk8s