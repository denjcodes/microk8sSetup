# Must RUN THIS AS ROOT AND BEFORE SCRIPT BELOW
mkdir setup && cd setup && touch setup.sh && chmod +x setup.sh && tee -a setup.sh << EOF
# !/bin/bash
if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit 1; fi
apt update && apt upgrade -y && apt-get install -y net-tools apt-transport-https ca-certificates curl nfs-common
EOF
./setup.sh && reboot


cd setup && truncate -s 0 setup.sh && nano setup.sh && ./setup.sh
#!/bin/bash
set -x
if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit 1; fi

sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo ufw default allow routed

sudo swapoff -a

sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo snap install microk8s --classic --channel=1.24/stable
microk8s status --wait-ready
sudo microk8s

sudo snap alias microk8s.kubectl kubectl
microk8s enable dns dashboard rbac helm3
microk8s enable metallb:172.16.49.100-172.16.49.120

tee -a metallb-ingress-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress
  namespace: ingress
spec:
  selector:
    name: nginx-ingress-microk8s
  type: LoadBalancer
  # If not "loadBalancerIP" is not defined, MetalLB will automatically an IP from its pool
  loadBalancerIP: 192.168.2.44
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
    - name: https
      protocol: TCP
      port: 443
      targetPort: 443
EOF

kubectl apply -f metallb-ingress-service.yaml
kubectl version --client

sudo snap install helm --classic
source /usr/share/bash-completion/bash_completion
echo 'source <(kubectl completion bash)' >>~/.bashrc
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert.sha256"
echo "$(cat kubectl-convert.sha256) kubectl-convert" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl && apt-mark hold kubelet kubeadm kubectl
kubectl config view --raw > ~/.kube/config && chmod g-r ~/.kube/config && chmod o-r ~/.kube/config

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
   cert-manager jetstack/cert-manager \
   --namespace cert-manager \
   --create-namespace \
   --version v1.7.1 \
   --set installCRDs=true

tee -a /etc/hosts << EOF
  192.168.2.45 k8sSlave1
  192.168.2.46 k8sSlave2
  192.168.2.47 k8sstorage
EOF


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
  accessModes:
    - ReadWriteOnce
  storageClassName: do-block-storage
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

kubectl apply -f wordpress-pv-volume.yaml

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

kubectl apply -f wordpress-pv-claim.yaml
kubectl get pv

kubectl describe secret | grep mysql- >> setupValues.txt
echo "Modifing the values for mysql-\n"

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

sleep 5
python3 modifyValues.py
sleep 5
kubectl apply -f mysql-service.yaml
sleep 5
kubectl apply -f wordpress-service.yaml

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
  - host: dennisjohnson.ca
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
    - dennisjohnson.ca
    secretName: wordpress-tls
EOF

cat > dashboard-adminuser.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

tee -a > admin-role-binding.yaml << EOF
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


kubectl apply -f wp_production_issuer.yaml
kubectl apply -f wordpress-ingress.yaml
kubectl apply -f dashboard-adminuser.yaml
kubectl apply -f admin-role-binding.yaml

token=$(kubectl -n kube-system get secret | grep default-token | cut -d " " -f1)
kubectl -n kube-system describe secret $token

echo "kubectl get all --all-namespaces"
echo "cat ~/.kube/config"
echo "microk8s add-node --token-ttl 7200"
kubectl get all --all-namespaces
cat ~/.kube/config
microk8s add-node --token-ttl 7200
# Xkq5Tp($L*^RC6p#Y8
