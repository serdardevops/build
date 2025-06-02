#!/bin/bash

# DevOps Kurulum Temizleme Scripti
# Kurulu tüm bileşenleri kaldırır ve sistemi temizler

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Makine bilgileri
MASTER_IP="192.168.1.137"
WORKER_IP="192.168.1.138"
MASTER_NAME="master"
WORKER_NAME="worker"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Kubernetes temizliği
cleanup_kubernetes() {
    log "Kubernetes temizleniyor..."
    
    # Kubernetes reset
    kubeadm reset -f || warn "kubeadm reset başarısız oldu, devam ediliyor..."
    
    # Kubernetes paketlerini kaldırma
    apt purge -y kubeadm kubectl kubelet kubernetes-cni || warn "Kubernetes paketleri kaldırılamadı, devam ediliyor..."
    
    # Kubernetes dizinlerini temizleme
    rm -rf /etc/kubernetes/ || warn "/etc/kubernetes/ temizlenemedi"
    rm -rf /var/lib/etcd/ || warn "/var/lib/etcd/ temizlenemedi"
    rm -rf /var/lib/kubelet/ || warn "/var/lib/kubelet/ temizlenemedi"
    rm -rf ~/.kube/ || warn "~/.kube/ temizlenemedi"
    rm -rf /home/ubuntu/.kube/ || warn "/home/ubuntu/.kube/ temizlenemedi"
    
    log "Kubernetes temizlendi"
}

# Docker temizliği
cleanup_docker() {
    log "Docker temizleniyor..."
    
    # Çalışan tüm container'ları durdur
    docker stop $(docker ps -aq) 2>/dev/null || warn "Çalışan container yok veya durdurulamadı"
    
    # Tüm container'ları kaldır
    docker rm $(docker ps -aq) 2>/dev/null || warn "Container'lar kaldırılamadı veya zaten kaldırılmış"
    
    # Tüm image'ları kaldır
    docker rmi $(docker images -q) 2>/dev/null || warn "Docker image'ları kaldırılamadı veya zaten kaldırılmış"
    
    # Docker paketlerini kaldır
    apt purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || warn "Docker paketleri kaldırılamadı"
    
    # Docker dizinlerini temizle
    rm -rf /var/lib/docker/ || warn "/var/lib/docker/ temizlenemedi"
    rm -rf /var/run/docker/ || warn "/var/run/docker/ temizlenemedi"
    
    log "Docker temizlendi"
}

# CNI temizliği
cleanup_cni() {
    log "CNI temizleniyor..."
    
    rm -rf /etc/cni/ || warn "/etc/cni/ temizlenemedi"
    rm -rf /opt/cni/ || warn "/opt/cni/ temizlenemedi"
    
    log "CNI temizlendi"
}

# Jenkins temizliği
cleanup_jenkins() {
    log "Jenkins temizleniyor..."
    
    systemctl stop jenkins || warn "Jenkins servis durdurulamadı"
    apt purge -y jenkins || warn "Jenkins paketi kaldırılamadı"
    rm -rf /var/lib/jenkins/ || warn "/var/lib/jenkins/ temizlenemedi"
    rm -f /home/ubuntu/jenkins-password.txt || warn "Jenkins şifre dosyası temizlenemedi"
    
    log "Jenkins temizlendi"
}

# SonarQube temizliği
cleanup_sonarqube() {
    log "SonarQube temizleniyor..."
    
    # SonarQube ayarları
    SONAR_USER="sonar"
    SONAR_HOME="/opt/sonarqube"
    SONAR_SERVICE_FILE="/etc/systemd/system/sonarqube.service"
    
    # SonarQube servisini durdur ve kaldır
    systemctl stop sonarqube 2>/dev/null || warn "SonarQube servis durdurulamadı"
    systemctl disable sonarqube 2>/dev/null || warn "SonarQube servis devre dışı bırakılamadı"
    rm -f $SONAR_SERVICE_FILE || warn "SonarQube servis dosyası temizlenemedi"
    systemctl daemon-reload
    
    # SonarQube dizinlerini temizle
    rm -rf $SONAR_HOME || warn "$SONAR_HOME temizlenemedi"
    
    # PostgreSQL temizliği
    sudo -u postgres dropdb sonarqube 2>/dev/null || warn "SonarQube veritabanı silinemedi"
    sudo -u postgres dropuser sonar 2>/dev/null || warn "SonarQube kullanıcısı silinemedi"
    
    # SonarQube kullanıcısını kaldır
    userdel -r $SONAR_USER 2>/dev/null || warn "sonar kullanıcısı silinemedi"
    
    # Sistem limitleri temizle
    sed -i '/vm.max_map_count=524288/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/fs.file-max=131072/d' /etc/sysctl.conf 2>/dev/null || true
    
    log "SonarQube temizlendi"
}

# ArgoCD temizliği
cleanup_argocd() {
    log "ArgoCD temizleniyor..."
    
    rm -f /usr/local/bin/argocd || warn "ArgoCD CLI temizlenemedi"
    rm -f /home/ubuntu/argocd-password.txt || warn "ArgoCD şifre dosyası temizlenemedi"
    
    log "ArgoCD temizlendi"
}

# Prometheus temizliği
cleanup_prometheus() {
    log "Prometheus temizleniyor..."
    
    systemctl stop prometheus 2>/dev/null || warn "Prometheus servis durdurulamadı"
    systemctl disable prometheus 2>/dev/null || warn "Prometheus servis devre dışı bırakılamadı"
    rm -f /etc/systemd/system/prometheus.service || warn "Prometheus servis dosyası temizlenemedi"
    
    rm -rf /etc/prometheus/ || warn "/etc/prometheus/ temizlenemedi"
    rm -rf /var/lib/prometheus/ || warn "/var/lib/prometheus/ temizlenemedi"
    rm -f /usr/local/bin/prometheus || warn "/usr/local/bin/prometheus temizlenemedi"
    rm -f /usr/local/bin/promtool || warn "/usr/local/bin/promtool temizlenemedi"
    
    userdel -r prometheus 2>/dev/null || warn "prometheus kullanıcısı silinemedi"
    
    log "Prometheus temizlendi"
}

# Grafana temizliği
cleanup_grafana() {
    log "Grafana temizleniyor..."
    
    systemctl stop grafana-server 2>/dev/null || warn "Grafana servis durdurulamadı"
    systemctl disable grafana-server 2>/dev/null || warn "Grafana servis devre dışı bırakılamadı"
    
    apt purge -y grafana || warn "Grafana paketi kaldırılamadı"
    rm -rf /var/lib/grafana/ || warn "/var/lib/grafana/ temizlenemedi"
    rm -rf /etc/grafana/ || warn "/etc/grafana/ temizlenemedi"
    
    # Grafana repo kaldır
    rm -f /etc/apt/sources.list.d/grafana.list || warn "Grafana repo dosyası temizlenemedi"
    
    log "Grafana temizlendi"
}

# Node Exporter temizliği
cleanup_node_exporter() {
    log "Node Exporter temizleniyor..."
    
    systemctl stop node_exporter 2>/dev/null || warn "Node Exporter servis durdurulamadı"
    systemctl disable node_exporter 2>/dev/null || warn "Node Exporter servis devre dışı bırakılamadı"
    rm -f /etc/systemd/system/node_exporter.service || warn "Node Exporter servis dosyası temizlenemedi"
    
    rm -f /usr/local/bin/node_exporter || warn "/usr/local/bin/node_exporter temizlenemedi"
    
    userdel -r node_exporter 2>/dev/null || warn "node_exporter kullanıcısı silinemedi"
    
    log "Node Exporter temizlendi"
}

# Firewall kurallarını temizle
cleanup_firewall() {
    log "Firewall kuralları temizleniyor..."
    
    ufw reset || warn "UFW kuralları sıfırlanamadı"
    ufw allow ssh || warn "SSH kuralı eklenemedi"
    ufw --force enable || warn "UFW etkinleştirilemedi"
    
    log "Firewall kuralları temizlendi"
}

# Iptables kurallarını temizle
cleanup_iptables() {
    log "Iptables kuralları temizleniyor..."
    
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X
    
    log "Iptables kuralları temizlendi"
}

# Ana temizleme fonksiyonu
main() {
    log "DevOps kurulumu temizleme işlemi başlatılıyor..."
    
    # Servisleri durdur
    systemctl stop kubelet || warn "kubelet durdurulamadı"
    systemctl stop docker || warn "docker durdurulamadı"
    systemctl stop containerd || warn "containerd durdurulamadı"
    
    # Bileşenleri temizle
    cleanup_kubernetes
    cleanup_docker
    cleanup_cni
    cleanup_jenkins
    cleanup_sonarqube
    cleanup_argocd
    cleanup_prometheus
    cleanup_grafana
    cleanup_node_exporter
    cleanup_firewall
    cleanup_iptables
    
    # Paket artıklarını temizle - zaman aşımı ekledik
    log "Paket artıkları temizleniyor..."
    timeout 300 apt autoremove -y || {
        warn "apt autoremove zaman aşımına uğradı veya başarısız oldu."
        warn "Alternatif temizleme yöntemi uygulanıyor..."
        apt-get clean
        apt-get update -y
    }
    
    log "Temizleme işlemi tamamlandı. Sistemi yeniden başlatmanız önerilir."
    log "Yeniden başlatmak için: sudo reboot"
}

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkileri gerektirmektedir. 'sudo ./cleanup-devops.sh' komutunu kullanın."
    exit 1
fi

# Onay al
read -p "Tüm DevOps bileşenleri ve yapılandırmaları kaldırılacak. Devam etmek istiyor musunuz? (e/h): " CONFIRM
if [ "$CONFIRM" != "e" ] && [ "$CONFIRM" != "E" ]; then
    log "İşlem iptal edildi."
    exit 0
fi

# Scripti çalıştır
main "$@" 