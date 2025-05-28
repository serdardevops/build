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

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
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
    
    # Hostname ve hosts dosyasını yapılandır
    hostnamectl set-hostname master
    echo "$MASTER_IP master" >> /etc/hosts
    echo "$WORKER_IP worker" >> /etc/hosts
    
    # Kubernetes master başlat
    log "Kubernetes master başlatılıyor..."
    
    # API sunucusu için gerekli port'un açık olduğunu kontrol et
    if ! nc -z localhost 6443; then
        log "Port 6443 erişilebilir durumda, devam ediliyor."
    else
        warn "Port 6443 zaten kullanımda. Önceki bir kurulum olabilir."
        log "Önceki kurulumu temizleme girişiminde bulunuluyor..."
        kubeadm reset -f || true
        systemctl restart kubelet containerd
        sleep 10
    fi
    
    # kubelet servisinin çalıştığından emin ol
    systemctl enable kubelet
    systemctl restart kubelet
    sleep 5
    
    # kubeadm init komutunu çalıştır
    if ! kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP; then
        error "Kubernetes master başlatılamadı. Hata ayıklama başlıyor..."
        
        # Hata ayıklama bilgilerini topla
        log "kubelet durumu kontrol ediliyor..."
        systemctl status kubelet
        
        log "kubelet günlükleri kontrol ediliyor..."
        journalctl -xeu kubelet | tail -n 50
        
        log "API sunucusu konteynerlerini kontrol ediliyor..."
        crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube | grep -v pause
        
        log "kube-apiserver günlükleri kontrol ediliyor..."
        for CID in $(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube-apiserver | awk '{print $1}'); do
            crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock logs $CID
        done
        
        log "Ağ yapılandırması kontrol ediliyor..."
        ip a
        
        log "DNS çözümlemesi kontrol ediliyor..."
        cat /etc/hosts
        
        log "Bellek durumu kontrol ediliyor..."
        free -m
        
        # Yaygın sorunları düzeltmeye çalış
        log "Yaygın sorunları düzeltme girişiminde bulunuluyor..."
        
        # containerd yeniden başlat
        systemctl restart containerd
        sleep 10
        
        # kubelet yeniden başlat
        systemctl restart kubelet
        sleep 10
        
        # Tekrar deneyin
        log "Kubernetes master'ı tekrar başlatmayı deneniyor..."
        kubeadm reset -f
        sleep 10
        
        # Daha fazla bellek için swap kontrolü
        if [ "$(free -m | awk '/^Swap:/ {print $2}')" -gt 0 ]; then
            log "Swap hala aktif, kapatılıyor..."
            swapoff -a
        fi
        
        # Son bir deneme
        if ! kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP --v=5; then
            error "Kubernetes master başlatılamadı. Lütfen manuel olarak sorun giderin."
            exit 1
        fi
    fi
    
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
    
    # Java 21 kurulumu - Ubuntu 24.04 için güncellendi
    apt install -y openjdk-21-jdk
    
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
        echo "wrapper.java.command=/usr/bin/java" > /opt/sonarqube/conf/wrapper.conf
        
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
    
    systemctl daemon-reload
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
    
    # ArgoCD'nin hazır olmasını bekle (60 saniye)
    log "ArgoCD'nin hazır olması bekleniyor..."
    sleep 60
    
    # ArgoCD admin şifresini al
    log "ArgoCD admin şifresi alınıyor..."
    ARGOCD_PASSWORD=""
    
    # initial-admin-secret'ten şifreyi almayı dene
    if kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d > /home/ubuntu/argocd-password.txt; then
        log "ArgoCD şifresi initial-admin-secret'ten alındı"
        ARGOCD_PASSWORD=$(cat /home/ubuntu/argocd-password.txt)
    else
        # initial-admin-secret bulunamadı, alternatif yöntem kullan
        log "ArgoCD initial-admin-secret bulunamadı, yeni şifre oluşturuluyor..."
        
        # Rastgele şifre oluştur
        NEW_PASSWORD=$(openssl rand -base64 12)
        
        # Şifreyi dosyaya kaydet
        echo "$NEW_PASSWORD" > /home/ubuntu/argocd-password.txt
        
        # ArgoCD şifresini değiştir
        kubectl -n argocd patch secret argocd-secret \
            -p '{"stringData": {
                "admin.password": "'$(htpasswd -bnBC 10 "" $NEW_PASSWORD | tr -d ':\n')'",
                "admin.passwordMtime": "'$(date +%FT%T%Z)'"
            }}'
        
        ARGOCD_PASSWORD=$NEW_PASSWORD
        log "ArgoCD için yeni şifre oluşturuldu"
    fi
    
    # Şifre dosyasının izinlerini düzenle
    chown ubuntu:ubuntu /home/ubuntu/argocd-password.txt
    chmod 600 /home/ubuntu/argocd-password.txt
    
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

# Kubernetes Cluster Yapılandırması
configure_cluster() {
    log "Cluster yapılandırması başlıyor..."
    
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    # Node'ların hazır olmasını bekle
    sleep 60
    
    # Metrics Server kurulumu
    log "Metrics Server kuruluyor..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Metrics server'ı self-signed certificate ile çalışacak şekilde patch et
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }
    ]'
    
    # Storage Class oluştur
    log "Local Storage Class oluşturuluyor..."
    cat > /tmp/local-storage-class.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
    
    kubectl apply -f /tmp/local-storage-class.yaml
    
    # Nginx örnek deployment
    log "Örnek uygulamalar oluşturuluyor..."
    cat > /tmp/nginx-example.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-example
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-example
  template:
    metadata:
      labels:
        app: nginx-example
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-example-service
  namespace: default
spec:
  selector:
    app: nginx-example
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30090
  type: NodePort
EOF
    
    kubectl apply -f /tmp/nginx-example.yaml
    
    # Resource quotas oluştur
    log "Resource quota'lar oluşturuluyor..."
    cat > /tmp/default-quota.yaml << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-quota
  namespace: default
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
EOF
    
    kubectl apply -f /tmp/default-quota.yaml
    
    # Cluster bilgilerini kaydet
    log "Cluster bilgileri kaydediliyor..."
    cat > /home/ubuntu/cluster-info.txt << EOF
=== KUBERNETES CLUSTER BİLGİLERİ ===

Cluster Durumu:
$(kubectl get nodes -o wide)

Çalışan Pod'lar:
$(kubectl get pods --all-namespaces)

Servisler:
$(kubectl get services --all-namespaces)

=== ERİŞİM BİLGİLERİ ===

Jenkins: http://$MASTER_IP:8080
- Admin şifresi: /home/ubuntu/jenkins-password.txt

SonarQube: http://$MASTER_IP:9000
- Varsayılan: admin/admin

ArgoCD: http://$MASTER_IP:30080
- Kullanıcı: admin
- Şifre: /home/ubuntu/argocd-password.txt

Kubernetes Dashboard: https://$MASTER_IP:30001
- Token: /home/ubuntu/dashboard-token.txt

Nginx Örnek: http://$MASTER_IP:30090

=== KUBECTL KOMUTLARI ===

# Cluster durumunu kontrol et
kubectl get nodes
kubectl get pods --all-namespaces

# Log'ları görüntüle
kubectl logs -f deployment/nginx-example

# Pod'lara erişim
kubectl exec -it <pod-name> -- /bin/bash

=== MONİTORİNG ===

Node Exporter (Worker): http://$WORKER_IP:9100/metrics

EOF
    
    chown ubuntu:ubuntu /home/ubuntu/cluster-info.txt
    
    log "Cluster bilgileri /home/ubuntu/cluster-info.txt dosyasına kaydedildi"
}

# Ağ ön gereksinimlerini kontrol et
check_network_prerequisites() {
    log "Ağ ön gereksinimleri kontrol ediliyor..."
    
    # Gerekli araçları kur
    apt install -y net-tools iputils-ping netcat-openbsd

    # Kernel modüllerini yükle
    log "Kernel modülleri yükleniyor..."
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Kernel parametrelerini ayarla
    log "Kernel parametreleri yapılandırılıyor..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system
    
    # IP adresi kontrolü
    log "IP adresi kontrolü yapılıyor..."
    CURRENT_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
    
    if [ "$CURRENT_IP" != "$MASTER_IP" ]; then
        warn "Yapılandırılan IP ($MASTER_IP) ile mevcut IP ($CURRENT_IP) eşleşmiyor."
        warn "Bu, kubeadm init sırasında sorunlara neden olabilir."
        
        # Doğru IP'yi kullanmak için kullanıcıya sor
        log "Doğru IP adresini kullanmak için aşağıdaki komutu çalıştırabilirsiniz:"
        log "MASTER_IP=$CURRENT_IP ./master-kurulum.sh"
        
        read -p "Yapılandırılan IP ($MASTER_IP) ile devam edilsin mi? (e/h): " CONTINUE
        if [ "$CONTINUE" != "e" ]; then
            log "IP düzeltmesi ile yeniden başlatılıyor..."
            MASTER_IP=$CURRENT_IP
            log "MASTER_IP=$MASTER_IP olarak ayarlandı."
        fi
    fi
    
    # Port kontrolü - 6443 açık mı?
    log "API server port kontrolü yapılıyor..."
    if nc -z localhost 6443; then
        warn "Port 6443 zaten kullanımda!"
        log "Port 6443'ü kullanan servis: $(lsof -i:6443 || netstat -tulpn | grep 6443)"
        
        read -p "Port 6443'ü kullanmaya çalışan servisleri durdurup devam etmek istiyor musunuz? (e/h): " STOP_SERVICE
        if [ "$STOP_SERVICE" == "e" ]; then
            log "6443 portunu kullanan servisleri durdurma girişiminde bulunuluyor..."
            
            # Önceki Kubernetes kurulumunu temizle
            if command -v kubeadm &> /dev/null; then
                kubeadm reset -f
            fi
            
            # containerd ve kubelet'i yeniden başlat
            systemctl stop kubelet containerd
            systemctl start containerd
            sleep 5
        else
            error "Port 6443 kullanımda ve servisler durdurulmadı. Kurulum iptal ediliyor."
            exit 1
        fi
    fi
    
    # DNS kontrolü
    log "DNS çözümleme kontrolü yapılıyor..."
    if ! host google.com > /dev/null 2>&1 && ! nslookup google.com > /dev/null 2>&1; then
        warn "DNS çözümlemesi çalışmıyor gibi görünüyor. Bu, container image'larını çekerken sorunlara neden olabilir."
        
        # DNS sunucuları kontrol et
        log "DNS yapılandırması kontrol ediliyor..."
        cat /etc/resolv.conf
        
        # Geçici çözüm olarak Google DNS ekle
        log "Geçici çözüm olarak Google DNS ekleniyor..."
        cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
$(cat /etc/resolv.conf)
EOF
    fi
    
    log "Ağ ön gereksinimleri kontrol edildi."
}

# Ana kurulum
main() {
    log "Master makine kurulumu başlıyor..."
    
    update_system
    check_network_prerequisites
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
    configure_cluster
    
    log "Master makine kurulumu tamamlandı!"
    log "Erişim bilgileri:"
    log "Jenkins: http://$MASTER_IP:8080"
    log "SonarQube: http://$MASTER_IP:9000"
    log "ArgoCD: http://$MASTER_IP:30080"
    log "Kubernetes Dashboard: https://$MASTER_IP:30001"
    log "Join komutu: /home/ubuntu/join-command.txt"
    log "Cluster bilgileri: /home/ubuntu/cluster-info.txt"
}

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkileri gerektirmektedir. 'sudo ./master-kurulum.sh' komutunu kullanın."
    exit 1
fi

# Scripti çalıştır
main "$@" 