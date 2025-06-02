#!/bin/bash

# Worker Makine Kurulum Scripti
# Docker, Kubernetes Worker Node

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
    
    log "Kubernetes kuruldu"
}

# Master'dan join komutu al ve cluster'a katıl
join_cluster() {
    log "Kubernetes cluster'a katılım bekleniyor..."
    
    # Master'da join komutu hazır olana kadar bekle
    while ! ssh -o ConnectTimeout=5 ubuntu@master "test -f /home/ubuntu/join-command.txt" 2>/dev/null; do
        log "Master'da join komutu bekleniyor..."
        sleep 30
    done
    
    # Join komutunu al ve çalıştır
    ssh ubuntu@master "cat /home/ubuntu/join-command.txt" > /tmp/join-command.txt
    chmod +x /tmp/join-command.txt
    
    log "Cluster'a katılım yapılıyor..."
    bash /tmp/join-command.txt
    
    log "Worker başarıyla cluster'a katıldı"
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

# Prometheus kurulumu
install_prometheus() {
    log "Prometheus kuruluyor..."
    
    # Prometheus kullanıcısı ve dizinleri
    useradd --no-create-home --shell /bin/false prometheus
    mkdir -p /etc/prometheus /var/lib/prometheus
    
    # Prometheus indirme
    cd /tmp
    if [ "$ARCH" == "arm64" ]; then
        wget https://github.com/prometheus/prometheus/releases/download/v2.50.0/prometheus-2.50.0.linux-arm64.tar.gz
        tar xvf prometheus-2.50.0.linux-arm64.tar.gz
        cp prometheus-2.50.0.linux-arm64/prometheus /usr/local/bin/
        cp prometheus-2.50.0.linux-arm64/promtool /usr/local/bin/
        cp -r prometheus-2.50.0.linux-arm64/consoles /etc/prometheus/
        cp -r prometheus-2.50.0.linux-arm64/console_libraries /etc/prometheus/
    else
        wget https://github.com/prometheus/prometheus/releases/download/v2.50.0/prometheus-2.50.0.linux-amd64.tar.gz
        tar xvf prometheus-2.50.0.linux-amd64.tar.gz
        cp prometheus-2.50.0.linux-amd64/prometheus /usr/local/bin/
        cp prometheus-2.50.0.linux-amd64/promtool /usr/local/bin/
        cp -r prometheus-2.50.0.linux-amd64/consoles /etc/prometheus/
        cp -r prometheus-2.50.0.linux-amd64/console_libraries /etc/prometheus/
    fi
    
    # İzinleri ayarla
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
    
    # Prometheus yapılandırması
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      # - alertmanager:9093

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['localhost:9090']
    
  - job_name: 'node_exporter'
    static_configs:
    - targets: ['localhost:9100', '$MASTER_IP:9100']
EOF
    
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    
    # Prometheus servis dosyası
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF
    
    # Prometheus'u başlat
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    # Firewall kuralları
    ufw allow 9090
    
    log "Prometheus kuruldu ve başlatıldı"
}

# Grafana kurulumu
install_grafana() {
    log "Grafana kuruluyor..."
    
    # Grafana GPG anahtarı ve repo
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
    
    apt update
    apt install -y grafana
    
    # Grafana'yı başlat
    systemctl enable grafana-server
    systemctl start grafana-server
    
    # Firewall kuralları
    ufw allow 3000
    
    log "Grafana kuruldu ve başlatıldı"
    log "Grafana web arayüzüne http://$WORKER_IP:3000 adresinden erişebilirsiniz."
    log "Varsayılan giriş bilgileri: admin / admin"
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
    install_prometheus
    install_grafana
    join_cluster
    
    log "Worker makine kurulumu tamamlandı!"
    log "Node bilgileri:"
    log "IP: $WORKER_IP"
    log "Role: Kubernetes Worker Node"
    log "Monitoring: Node Exporter (Port 9100)"
    log "Prometheus: http://$WORKER_IP:9090"
    log "Grafana: http://$WORKER_IP:3000"
}

main "$@" 