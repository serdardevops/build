#!/bin/bash

# IP Güncelleme Scripti
# Master ve Worker IP adreslerini tüm kurulum scriptlerinde günceller

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

# Mevcut IP adreslerini al
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_SCRIPT="$SCRIPT_DIR/master-kurulum.sh"
WORKER_SCRIPT="$SCRIPT_DIR/worker-kurulum.sh"
README_FILE="$SCRIPT_DIR/README.md"

# Mevcut değerleri kontrol et
if [ -f "$MASTER_SCRIPT" ]; then
    CURRENT_MASTER_IP=$(grep -oP 'MASTER_IP="\K[^"]+' "$MASTER_SCRIPT")
    CURRENT_WORKER_IP=$(grep -oP 'WORKER_IP="\K[^"]+' "$MASTER_SCRIPT")
    log "Mevcut IP Adresleri:"
    log "Master IP: $CURRENT_MASTER_IP"
    log "Worker IP: $CURRENT_WORKER_IP"
else
    error "Master kurulum scripti bulunamadı: $MASTER_SCRIPT"
    exit 1
fi

# Yeni IP değerlerini al
read -p "Yeni Master IP adresini girin [$CURRENT_MASTER_IP]: " NEW_MASTER_IP
NEW_MASTER_IP=${NEW_MASTER_IP:-$CURRENT_MASTER_IP}

read -p "Yeni Worker IP adresini girin [$CURRENT_WORKER_IP]: " NEW_WORKER_IP
NEW_WORKER_IP=${NEW_WORKER_IP:-$CURRENT_WORKER_IP}

# Scriptlerde IP değişikliği yap
update_file_ips() {
    local file=$1
    local old_master_ip=$2
    local new_master_ip=$3
    local old_worker_ip=$4
    local new_worker_ip=$5
    
    if [ -f "$file" ]; then
        log "$file dosyasında IP adresleri güncelleniyor..."
        
        # IP değişikliklerini yap
        sed -i "s/MASTER_IP=\"$old_master_ip\"/MASTER_IP=\"$new_master_ip\"/g" "$file"
        sed -i "s/WORKER_IP=\"$old_worker_ip\"/WORKER_IP=\"$new_worker_ip\"/g" "$file"
        
        # Diğer olası IP referanslarını güncelle
        sed -i "s/$old_master_ip/$new_master_ip/g" "$file"
        sed -i "s/$old_worker_ip/$new_worker_ip/g" "$file"
        
        log "$file dosyasında IP adresleri güncellendi."
    else
        warn "$file dosyası bulunamadı, atlanıyor."
    fi
}

# README dosyasını güncelle
update_readme() {
    local file=$1
    local old_master_ip=$2
    local new_master_ip=$3
    local old_worker_ip=$4
    local new_worker_ip=$5
    
    if [ -f "$file" ]; then
        log "$file dosyasında IP adresleri güncelleniyor..."
        
        # IP değişikliklerini yap
        sed -i "s/$old_master_ip/$new_master_ip/g" "$file"
        sed -i "s/$old_worker_ip/$new_worker_ip/g" "$file"
        
        log "$file dosyasında IP adresleri güncellendi."
    else
        warn "$file dosyası bulunamadı, atlanıyor."
    fi
}

# IP adreslerini güncelle
update_file_ips "$MASTER_SCRIPT" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"
update_file_ips "$WORKER_SCRIPT" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"
update_readme "$README_FILE" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"

# Çalışır hale getir
chmod +x "$MASTER_SCRIPT" "$WORKER_SCRIPT"

log "IP güncelleme işlemi tamamlandı!"
log "Yeni Master IP: $NEW_MASTER_IP"
log "Yeni Worker IP: $NEW_WORKER_IP"
log ""
log "Kurulum scriptlerini aşağıdaki gibi çalıştırabilirsiniz:"
log "Master: sudo $MASTER_SCRIPT"
log "Worker: sudo $WORKER_SCRIPT" 