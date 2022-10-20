#!/bin/bash
set -x
sudo snap install microk8s --classic
sudo ufw allow in on cni0 && sudo ufw allow out on cni0
alias kubectl="microk8s kubectl"
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
microk8s kubectl config view --raw > ~/.kube/config
chmod g-r ~/.kube/config
chmod o-r ~/.kube/config

helm upgrade --install ingress-nginx ingress-nginx \
   --repo https://kubernetes.github.io/ingress-nginx \
   --namespace ingress-nginx --create-namespace

#helm repo add bitnami https://charts.bitnami.com/bitnami
#helm install my-release bitnami/wordpress
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

kubectl describe secret | grep mysql-
echo "Modify the values for mysql-\n"

tee -a wordpress-service.yaml << EOF
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
kubectl apply -f wordpress-service.yaml

tee -a wp_production_issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: wp-prod-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: budi@busanid.dev
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl apply -f wp_production_issuer.yaml

tee -a  wordpress_ingress.yaml << EOF
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
kubectl apply -f wordpress_ingress.yaml


kubectl enable dns dashboard storage rbac helm3 cert-manager

cat > dashboard-adminuser.yml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

kubectl apply -f dashboard-adminuser.yml

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

kubectl apply -f admin-role-binding.yml

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

token=$(microk8s kubectl -n kube-system get secret | grep default-token | cut -d " " -f1)
microk8s kubectl -n kube-system describe secret $token


snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

tee -a > acme-challenge.yaml << EOF
- path: /.well-known/acme-challenge
  pathType: Prefix
  backend:
    serviceName: acme-challenge
    servicePort: 80
EOF