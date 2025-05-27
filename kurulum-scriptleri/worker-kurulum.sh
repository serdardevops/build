#!/bin/bash

# Worker Makine Kurulum Scripti
# Docker, Kubernetes Worker Node, Node Exporter

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
    
    # Kubernetes worker node portları
    ufw allow 10250  # kubelet
    ufw allow 10255  # kubelet read-only
    ufw allow 30000:32767/tcp  # NodePort services
    
    # CNI portları (Flannel/Calico)
    ufw allow 8285/udp
    ufw allow 8472/udp
    
    # Master ile iletişim
    ufw allow from $MASTER_IP
    
    # Pod-to-pod communication
    ufw allow 10244.0.0.0/16
    
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
    hostnamectl set-hostname worker
    echo "$MASTER_IP master" >> /etc/hosts
    echo "$WORKER_IP worker" >> /etc/hosts
    
    log "Kubernetes kuruldu"
}

# Monitoring araçları kurulumu
install_monitoring() {
    log "Monitoring araçları kuruluyor..."
    
    # Node Exporter kurulumu (Prometheus monitoring için)
    useradd --no-create-home --shell /bin/false node_exporter
    
    cd /tmp
    # Mimari bazlı Node Exporter indirme
    if [ "$ARCH" == "arm64" ]; then
        wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-arm64.tar.gz
        tar xvf node_exporter-1.8.2.linux-arm64.tar.gz
        cp node_exporter-1.8.2.linux-arm64/node_exporter /usr/local/bin/
    else
        wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
        tar xvf node_exporter-1.8.2.linux-amd64.tar.gz
        cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
    fi
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    
    # Node Exporter systemd service
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    # Port 9100'ü aç (Node Exporter)
    ufw allow 9100
    
    log "Node Exporter kuruldu"
}

# Sistem optimizasyonları
optimize_system() {
    log "Sistem optimizasyonları yapılıyor..."
    
    # Kernel parametreleri
    cat >> /etc/sysctl.conf << EOF

# Kubernetes optimizations
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1

# Docker optimizations
vm.max_map_count = 262144
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
    
    sysctl --system
    
    # br_netfilter modülü
    modprobe br_netfilter
    echo 'br_netfilter' >> /etc/modules-load.d/k8s.conf
    
    log "Sistem optimizasyonları tamamlandı"
}

# Log rotation yapılandırması
setup_log_rotation() {
    log "Log rotation yapılandırılıyor..."
    
    # Docker log rotation
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
    
    systemctl restart docker
    
    # Kubernetes log cleanup cron job
    cat > /etc/cron.daily/k8s-log-cleanup << EOF
#!/bin/bash
# Clean old kubernetes logs
find /var/log/pods -type f -name "*.log" -mtime +7 -delete
find /var/lib/docker/containers -type f -name "*-json.log" -mtime +7 -delete
EOF
    
    chmod +x /etc/cron.daily/k8s-log-cleanup
    
    log "Log rotation yapılandırıldı"
}

# Master'dan join komutu kopyalanınca çalıştırma bilgisi
show_join_instructions() {
    log "Kubernetes kurulumu tamamlandı."
    log "Şimdi master makinede aşağıdaki komutu çalıştırın:"
    log "cat /home/ubuntu/join-command.txt"
    log ""
    log "Komut çıktısını kopyalayıp bu makinede çalıştırın:"
    log "sudo kubeadm join ..."
    log ""
    log "Veya master makinede join komutunu almanız için şu komutu çalıştırın:"
    log "cat /home/ubuntu/join-command.txt | ssh ubuntu@$WORKER_IP \"sudo bash\""
}

# Ana kurulum
main() {
    log "Worker makine kurulumu başlıyor..."
    
    update_system
    setup_firewall
    install_docker
    install_kubernetes
    optimize_system
    setup_log_rotation
    install_monitoring
    show_join_instructions
    
    log "Worker makine kurulumu tamamlandı!"
    log "Node bilgileri:"
    log "IP: $WORKER_IP"
    log "Role: Kubernetes Worker Node"
    log "Monitoring: Node Exporter (Port 9100)"
    log ""
    log "Master makinesinden join komutunu alıp çalıştırmayı unutmayın."
}

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkileri gerektirmektedir. 'sudo ./worker-kurulum.sh' komutunu kullanın."
    exit 1
fi

# Scripti çalıştır
main "$@" 