#!/bin/bash

# DevOps Araçları Kurulum Scripti
# Master ve Worker makineleri için otomatik kurulum

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonu
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Sistem mimarisi kontrolü
check_architecture() {
    ARCH=$(dpkg --print-architecture)
    log "Sistem mimarisi: $ARCH"
    
    if [ "$ARCH" == "arm64" ]; then
        log "ARM64 mimarisi tespit edildi. Kurulum buna göre yapılandırılacak."
    elif [ "$ARCH" == "amd64" ]; then
        log "AMD64 mimarisi tespit edildi. Kurulum buna göre yapılandırılacak."
    else
        warn "Desteklenmeyen mimari: $ARCH. Kurulum devam edecek ancak sorunlar olabilir."
    fi
}

# Makine bilgileri
MASTER_IP="192.168.1.131"
WORKER_IP="192.168.1.127"
MASTER_NAME="master"
WORKER_NAME="worker"

# SSH anahtarı oluştur
setup_ssh_keys() {
    log "SSH anahtarları oluşturuluyor..."
    
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log "SSH anahtarı oluşturuldu"
    else
        log "SSH anahtarı zaten mevcut"
    fi
}

# Scriptleri makinelere kopyala ve çalıştır
deploy_and_run() {
    local machine_name=$1
    local script_name=$2
    
    log "Script $script_name $machine_name makinesine kopyalanıyor..."
    
    # Eğer makine adı "master" ve "hostname" komutu "master" döndürüyorsa aynı makinedeyiz
    if [ "$machine_name" = "master" ] && [ "$(hostname)" = "master" ]; then
        log "Kurulum yerel master makinede yapılıyor..."
        chmod +x $script_name
        sudo ./$script_name
    elif [ "$machine_name" = "worker" ] && [ "$(hostname)" = "worker" ]; then
        log "Kurulum yerel worker makinede yapılıyor..."
        chmod +x $script_name
        sudo ./$script_name
    else
        # SSH anahtarını kopyala
        ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@$machine_name 2>/dev/null || true
        
        # Scripti kopyala
        scp $script_name ubuntu@$machine_name:/tmp/
        
        # Scripti çalıştırılabilir yap ve çalıştır
        ssh ubuntu@$machine_name "chmod +x /tmp/$script_name && sudo /tmp/$script_name"
    fi
}

# Ana kurulum sürecini başlat
main() {
    log "DevOps araçları kurulum sürecine başlanıyor..."
    log "Master IP: $MASTER_IP"
    log "Worker IP: $WORKER_IP"
    
    # Sistem mimarisini kontrol et
    check_architecture
    
    # SSH anahtarlarını hazırla
    setup_ssh_keys
    
    # Master makinesine kurulum
    log "Master makinesinde kurulum başlatılıyor..."
    deploy_and_run $MASTER_NAME "master-setup.sh"
    
    # Worker makinesine kurulum
    log "Worker makinesinde kurulum başlatılıyor..."
    deploy_and_run $WORKER_NAME "worker-setup.sh"
    
    # Kubernetes cluster kurulumu
    log "Kubernetes cluster yapılandırması başlatılıyor..."
    if [ "$(hostname)" = "master" ]; then
        log "Cluster yapılandırması yerel master makinede yapılıyor..."
        chmod +x configure-cluster.sh
        sudo ./configure-cluster.sh
    else
        ssh ubuntu@$MASTER_NAME "sudo /tmp/configure-cluster.sh"
    fi
    
    log "Tüm kurulumlar tamamlandı!"
    log "Erişim bilgileri:"
    log "Jenkins: http://$MASTER_IP:8080"
    log "SonarQube: http://$MASTER_IP:9000"
    log "ArgoCD: http://$MASTER_IP:30080"
    log "Kubernetes Dashboard: http://$MASTER_IP:30001"
}

# Scripti çalıştır
main "$@" 