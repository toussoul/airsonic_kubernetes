### need to use dhcp and install ssh on hyper-V and execute the first part to set a static ip ###


# Set ip static 
  # UUIDeth0=$(cat /etc/sysconfig/network-scripts/ifcfg-eth0 | grep UUID)
  # cyberciti.biz/faq/howto-setting-rhel7-centos-7-static-ip-configuration/
  # echo $'TYPE=Ethernet\nBOOTPROTO=none\nIPADDR=172.18.200.5\nPREFIX=24\nGATEWAY=172.18.200.1\nDNS1=172.18.200.2\nDNS2=172.18.200.3\nDEFROUTE=yes\nIPV4_FAILURE_FATAL=no\nIPV6INIT=no\nNAME=eth0\n'$UUIDeth0$'\nDEVICE=eth0\nONBOOT=yes' > /etc/sysconfig/network-scripts/ifcfg-eth0
  # systemctl restart network

# install docker and other tools needed 
  yum check-update
  sleep 5
  yum install -y yum-utils device-mapper-persistent-data lvm2 nfs-utils nfs-utils-lib epel-release
  sleep 5
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum install docker-ce -y
  sleep 5
  systemctl enable --now docker

# add the kubernetes repo
cat <<EOF |  tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# component for kubernete
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sleep 5
systemctl enable --now kubelet
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
sleep 5
rm minikube-linux-amd64 -f

# create airsonic dir 
mkdir /airsonic/
chmod 777 /airsonic/ -R
minikube config set driver docker
# useradd kubeuser
# printf "user\nuser\n" | passwd kubeuser
# usermod -aG docker kubeuser && newgrp docker
# echo "kubeuser ALL = (root) NOPASSWD: /usr/local/bin/minikube" >> /etc/sudoers
# su kubeuser
# cd ~

# airsonic minikube file
cat > /airsonic/Airsonic.yaml <<EOF
### Note: you must configure access to your media folder. This example uses an NFS mount ###

apiVersion: apps/v1
kind: Deployment
metadata:
  name: airsonic
spec:
  replicas: 1
  selector:
    matchLabels:
      app: airsonic
  template:
    metadata:
      labels:
        app: airsonic
    spec:
      containers:
      - image: airsonicadvanced/airsonic-advanced
        resources:
          requests:
            memory: "1000Mi"
            cpu: "1000m"
          limits:
            memory: "2000Mi"
            cpu: "2000m"
        env:
        - name: AIRSONIC_PORT
          value: "4040"
        - name: JAVA_OPTS
          value: -Xmx512m
        name: airsonic
        ports:
          - containerPort: 4040
        volumeMounts:
        - mountPath: /var/airsonic/airsonic.properties
          name: remotedata
          subPath: config/airsonic.properties
        - mountPath: /var/airsonic/transcode
          name: remotedata
          subPath: config/transcode
        - mountPath: /var/airsonic/index19
          name: remotedata
          subPath: config/index19
        - mountPath: /var/airsonic/thumbs
          name: remotedata
          subPath: config/thumbs
        - mountPath: /var/airsonic/lastfmcache
          name: remotedata
          subPath: config/lastfmcache
        - mountPath: /var/data
          name: remotedata
          subPath: data
        - mountPath: /var/music
          name: remotedata
          subPath: music
        - mountPath: /var/playlists
          name: remotedata
          subPath: playlists
        - mountPath: /var/podcasts
          name: remotedata
          subPath: podcasts
        - mountPath: /app/icons/default_light/logo.png
          name: remotedata
          subPath: logo.png
      restartPolicy: Always
      volumes:
      # Please configure for your media share
      # See this document for additional volume types: https://kubernetes.io/docs/concepts/storage/volumes/
      - name: remotedata
        nfs:
          server: PAR_DFS1-spare.airzik.live
          path: /Airsonic
---
apiVersion: v1
kind: Service
metadata:
  name: airsonic
spec:
  type: LoadBalancer
  ports:
    - port: 4040
      targetPort: 4040
      protocol: TCP
  selector:
    app: airsonic
status:
  loadBalancer: {}
EOF

cat > /airsonic/hpa.yaml <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: airsonic
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: airsonic
  minReplicas: 1
  maxReplicas: 10
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
      policies:
      - type: Pods
        value: 8
        periodSeconds: 30
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Pods
        value: 2
        periodSeconds: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
EOF

cat > /airsonic/mariadb.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
spec:
  selector:
    matchLabels:
      app: mariadb
  replicas: 1
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:latest
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: g#c@J@0haNmx5n3K7l1m
        ports:
        - containerPort: 3306
        volumeMounts:
        - mountPath: /var/lib/mysql
          name: mariadb-data
      volumes:
      # Please configure for your media share
      # See this document for additional volume types: https://kubernetes.io/docs/concepts/storage/volumes/
      - name: mariadb-data
        nfs:
          server: PAR_DFS1-spare.airzik.live
          path: /mariadb
---
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  labels:
    app: mariadb
spec:
  ports:
  - port: 3306
    targetPort: 3306
    name: mariadb
  selector:
    app: mariadb
  type: ClusterIP
EOF

# adapt to the correct port
firewall-cmd --permanent --zone=public --add-port=3306/tcp
firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --reload

# install metrics-server for kubernete hpa
  # kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# create name space 
  # kubectl create namespace airsonic

# apply the mariadb deplouyment and create the database airsonic
  # kubectl apply -f /airsonic/mariadb.yaml --namespace airsonic
  # sleep 10
  # kubectl exec -it $(kubectl get pods --namespace airsonic -o name | grep mariadb) --namespace airsonic -- /bin/bash -c 'mariadb -u root -pg#c@J@0haNmx5n3K7l1m -e "create database if not exists airsonic"'
  # kubectl exec -it $(kubectl get pods --namespace airsonic -o name | grep mariadb) --namespace airsonic -- /bin/bash -c 'mariadb -u root -pg#c@J@0haNmx5n3K7l1m -e "drop database airsonic"'
  # kubectl port-forward service/mariadb 3306:3306 --namespace airsonic --address 0.0.0.0 &


# need to add this line to the airsonic.properties file
    # DatabaseConfigType=embed
    # DatabaseConfigEmbedDriver=org.mariadb.jdbc.Driver
    # DatabaseConfigEmbedUrl=jdbc:mariadb://kubernetes:3306/airsonic
    # DatabaseConfigEmbedUsername=root
    # DatabaseConfigEmbedPassword=g#c@J@0haNmx5n3K7l1m

# Apply the airsonic deployement and the autoscaling service 
  # kubectl apply -f /airsonic/Airsonic.yaml --namespace airsonic
  # kubectl apply -f /airsonic/hpa.yaml --namespace airsonic


cat > /etc/cron.d/kuberneteStart.sh << EOF

/usr/local/bin/minikube start --force
/usr/local/bin/minikube addons enable metrics-server
sleep 10
/usr/local/bin/minikube tunnel &> /dev/null &
/bin/kubectl create namespace airsonic

/bin/kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
/bin/kubectl apply -f /airsonic/mariadb.yaml --namespace airsonic
# sleep 5
/bin/kubectl exec -it \$(/bin/kubectl get pods --namespace airsonic -o name | /bin/grep mariadb) --namespace airsonic -- /bin/bash -c 'mariadb -u root -pg#c@J@0haNmx5n3K7l1m -e "create database if not exists airsonic"'
# sleep 5
/bin/kubectl port-forward service/mariadb 3306:3306 --namespace airsonic --address 0.0.0.0 &
sleep 5
/bin/kubectl apply -f /airsonic/Airsonic.yaml --namespace airsonic
/bin/kubectl apply -f /airsonic/hpa.yaml --namespace airsonic

function fixForwardSQL(){ if (/bin/kubectl port-forward service/mariadb 3306:3306 --namespace airsonic --address 0.0.0.0 --pod-running-timeout=5s --log-file=~/test --logtostderr=false 2>&1 | grep error); then echo Error && (fixForwardSQL &); fi };
fixForwardSQL &
function fixForwardHTTP(){ if (/bin/kubectl port-forward service/airsonic 80:4040 --namespace airsonic --address 0.0.0.0 --pod-running-timeout=5s --log-file=~/test --logtostderr=false 2>&1 | grep error); then echo Error && (fixForwardHTTP &); fi };
fixForwardHTTP &

EOF

cat > /etc/cron.d/kuberneteStop.sh << EOF

/bin/kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
/bin/kubectl delete -f /airsonic/mariadb.yaml --namespace airsonic
/bin/kubectl delete -f /airsonic/Airsonic.yaml --namespace airsonic
/bin/kubectl delete -f /airsonic/hpa.yaml --namespace airsonic

/usr/local/bin/minikube stop

EOF

chmod +x /etc/cron.d/kuberneteStop.sh
chmod +x /etc/cron.d/kuberneteStart.sh

cat > /usr/lib/systemd/system/minikube.service << EOF
[Unit]
Description=minikube
After=network-online.target firewalld.service containerd.service docker.service
Wants=network-online.target docker.service
Requires=docker.socket containerd.service docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/root
ExecStart=/bin/sh -c /etc/cron.d/kuberneteStart.sh
ExecStop=/bin/sh -c /etc/cron.d/kuberneteStop.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload 
systemctl unmask minikube
systemctl enable --now minikube