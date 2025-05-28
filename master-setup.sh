#!/bin/bash

# Master Makine Kurulum Scripti
# Docker, Kubernetes Master, Jenkins, SonarQube, ArgoCD, Helm

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# IP adresleri
MASTER_IP="192.168.1.137"
WORKER_IP="192.168.1.138"

# Mimariye göre mimari değişkenini belirle
ARCH=$(dpkg --print-architecture)
log "Sistem mimarisi: $ARCH"

# Sistem güncellemesi
update_system() {
    log "Sistem güncelleniyor..."
    apt update && apt upgrade -y
    apt install -y curl wget git vim htop net-tools ufw unzip
}

# Firewall yapılandırması
setup_firewall() {
    log "Firewall yapılandırılıyor..."
    
    # UFW'yi etkinleştir
    ufw --force enable
    
    # SSH erişimi
    ufw allow ssh
    ufw allow 22
    
    # Kubernetes portları
    ufw allow 6443  # Kubernetes API
    ufw allow 2379:2380/tcp  # etcd
    ufw allow 10250  # kubelet
    ufw allow 10251  # kube-scheduler
    ufw allow 10252  # kube-controller-manager
    ufw allow 10255  # kubelet read-only
    
    # CNI portları (Flannel/Calico)
    ufw allow 8285/udp
    ufw allow 8472/udp
    
    # Jenkins
    ufw allow 8080
    
    # SonarQube
    ufw allow 9000
    
    # ArgoCD
    ufw allow 30080
    
    # Worker ile iletişim
    ufw allow from $WORKER_IP
    
    # NodePort aralığı
    ufw allow 30000:32767/tcp
    
    log "Firewall kuralları uygulandı"
}

# Docker kurulumu
install_docker() {
    log "Docker kuruluyor..."
    
    # Eski Docker sürümlerini kaldır
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Docker GPG anahtarı ve repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Mimari bazlı repository ekleme
    echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Docker servisini başlat
    systemctl enable docker
    systemctl start docker
    
    # Ubuntu kullanıcısını docker grubuna ekle
    usermod -aG docker ubuntu
    
    log "Docker kuruldu"
}

# Kubernetes kurulumu
install_kubernetes() {
    log "Kubernetes kuruluyor..."
    
    # Swap'ı kapat
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Kubernetes repository - Ubuntu 24.04 Noble için güncellendi
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    
    apt update
    apt install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    
    # containerd yapılandırması
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    
    # Kubernetes master başlat
    kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP
    
    # kubectl yapılandırması
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown ubuntu:ubuntu /home/ubuntu/.kube/config
    
    # Root için kubectl
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    log "Kubernetes master kuruldu"
}

# CNI (Flannel) kurulumu
install_cni() {
    log "Flannel CNI kuruluyor..."
    
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
    
    log "Flannel CNI kuruldu"
}

# Helm kurulumu
install_helm() {
    log "Helm kuruluyor..."
    
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    apt update
    apt install -y helm
    
    log "Helm kuruldu"
}

# Jenkins kurulumu
install_jenkins() {
    log "Jenkins kuruluyor..."
    
    # Java 17 kurulumu
    apt install -y openjdk-17-jdk
    
    # Jenkins repository
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    
    apt update
    apt install -y jenkins
    
    # Jenkins servisini başlat
    systemctl enable jenkins
    systemctl start jenkins
    
    # İlk admin şifresini al
    sleep 30
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
        JENKINS_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
        echo "Jenkins İlk Admin Şifresi: $JENKINS_PASSWORD" > /home/ubuntu/jenkins-password.txt
        chown ubuntu:ubuntu /home/ubuntu/jenkins-password.txt
    fi
    
    log "Jenkins kuruldu - Şifre /home/ubuntu/jenkins-password.txt dosyasında"
}

# SonarQube kurulumu
install_sonarqube() {
    log "SonarQube kuruluyor..."
    
    # PostgreSQL kurulumu
    apt install -y postgresql postgresql-contrib
    
    # SonarQube veritabanı
    sudo -u postgres createuser sonar
    sudo -u postgres psql -c "ALTER USER sonar WITH PASSWORD 'sonar';"
    sudo -u postgres createdb sonarqube -O sonar
    
    # SonarQube kullanıcısı
    useradd -m -s /bin/bash sonar
    
    # SonarQube indirme ve kurulum
    cd /opt
    
    # Mimari kontrolü ve uygun SonarQube sürümünü indirme
    if [ "$ARCH" == "arm64" ]; then
        log "ARM64 mimarisi için SonarQube Community Edition indiriliyor..."
        wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
        unzip sonarqube-9.9.0.65466.zip
        mv sonarqube-9.9.0.65466 sonarqube
        
        # ARM64 için wrapper.conf oluşturma ve düzenleme
        mkdir -p /opt/sonarqube/conf/
        echo "wrapper.java.command=/usr/lib/jvm/java-17-openjdk-arm64/bin/java" > /opt/sonarqube/conf/wrapper.conf
        
        # SonarQube başlatma scriptini ARM için düzenle
        if [ ! -d "/opt/sonarqube/bin/linux-arm64" ]; then
            mkdir -p /opt/sonarqube/bin/linux-arm64
            cp /opt/sonarqube/bin/linux-x86-64/sonar.sh /opt/sonarqube/bin/linux-arm64/
            chmod +x /opt/sonarqube/bin/linux-arm64/sonar.sh
        fi
    else
        wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
        unzip sonarqube-9.9.0.65466.zip
        mv sonarqube-9.9.0.65466 sonarqube
        
        # X86_64 için wrapper.conf oluşturma ve düzenleme
        mkdir -p /opt/sonarqube/conf/
        echo "wrapper.java.command=/usr/lib/jvm/java-17-openjdk-amd64/bin/java" > /opt/sonarqube/conf/wrapper.conf
    fi
    
    chown -R sonar:sonar sonarqube
    
    # SonarQube yapılandırması
    cat > /opt/sonarqube/conf/sonar.properties << EOF
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
EOF
    
    # Systemd servis dosyası
    cat > /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-$ARCH/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-$ARCH/sonar.sh stop
User=sonar
Group=sonar
Restart=always
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable sonarqube
    systemctl start sonarqube
    
    log "SonarQube kuruldu"
}

# ArgoCD kurulumu
install_argocd() {
    log "ArgoCD kuruluyor..."
    
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    # ArgoCD namespace oluştur
    kubectl create namespace argocd
    
    # ArgoCD kurulumu
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # ArgoCD server'ı NodePort olarak expose et
    kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080}]}}'
    
    # ArgoCD CLI kurulumu
    if [ "$ARCH" == "arm64" ]; then
        curl -sSL -o argocd-linux-arm64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
        install -m 555 argocd-linux-arm64 /usr/local/bin/argocd
        rm argocd-linux-arm64
    else
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
    fi
    
    # ArgoCD admin şifresini al
    sleep 60
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "ArgoCD Admin Şifresi: $ARGOCD_PASSWORD" > /home/ubuntu/argocd-password.txt
    chown ubuntu:ubuntu /home/ubuntu/argocd-password.txt
    
    log "ArgoCD kuruldu - Şifre /home/ubuntu/argocd-password.txt dosyasında"
}

# Kubernetes Dashboard kurulumu
install_k8s_dashboard() {
    log "Kubernetes Dashboard kuruluyor..."
    
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    # Dashboard kurulumu
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    
    # Dashboard'ı NodePort olarak expose et
    kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8443,"nodePort":30001}]}}'
    
    # Admin kullanıcı oluştur
    cat > /tmp/dashboard-admin.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
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
  namespace: kubernetes-dashboard
EOF
    
    kubectl apply -f /tmp/dashboard-admin.yaml
    
    # Token oluştur ve kaydet
    kubectl create token admin-user -n kubernetes-dashboard > /home/ubuntu/dashboard-token.txt
    chown ubuntu:ubuntu /home/ubuntu/dashboard-token.txt
    
    log "Kubernetes Dashboard kuruldu - Token /home/ubuntu/dashboard-token.txt dosyasında"
}

# Join token oluştur
create_join_token() {
    log "Node join token oluşturuluyor..."
    
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubeadm token create --print-join-command > /home/ubuntu/join-command.txt
    chown ubuntu:ubuntu /home/ubuntu/join-command.txt
    
    log "Join komutu /home/ubuntu/join-command.txt dosyasında"
}

# Ana kurulum
main() {
    log "Master makine kurulumu başlıyor..."
    
    update_system
    setup_firewall
    install_docker
    install_kubernetes
    install_cni
    install_helm
    install_jenkins
    install_sonarqube
    install_argocd
    install_k8s_dashboard
    create_join_token
    
    log "Master makine kurulumu tamamlandı!"
    log "Erişim bilgileri:"
    log "Jenkins: http://$MASTER_IP:8080"
    log "SonarQube: http://$MASTER_IP:9000"
    log "ArgoCD: http://$MASTER_IP:30080"
    log "Kubernetes Dashboard: https://$MASTER_IP:30001"
}

main "$@" 