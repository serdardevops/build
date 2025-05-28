#!/bin/bash

# IP Otomatik Güncelleme Scripti
# Sistemin IP adreslerini otomatik tespit eder ve kurulum scriptlerini günceller

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

# Dosya yollarını belirle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_SCRIPT="$SCRIPT_DIR/master-kurulum.sh"
WORKER_SCRIPT="$SCRIPT_DIR/worker-kurulum.sh"
README_FILE="$SCRIPT_DIR/README.md"

# Mevcut IP adreslerini tespit et
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

# Sistemin IP adresini otomatik tespit et
detect_system_ip() {
    # İşletim sistemini tespit et
    OS_TYPE=$(uname)
    
    if [ "$OS_TYPE" == "Darwin" ]; then
        # Mac OS X için IP tespiti
        SYSTEM_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
    else
        # Linux için IP tespiti
        SYSTEM_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
    fi
    
    echo "$SYSTEM_IP"
}

# Sistemin IP adresini al
SYSTEM_IP=$(detect_system_ip)
log "Tespit edilen sistem IP adresi: $SYSTEM_IP"

# Hangi makine olduğunu kullanıcıya sor
echo "Bu sistemi nasıl yapılandırmak istiyorsunuz?"
echo "1) Master makine (Kubernetes master, Jenkins, SonarQube, vb.)"
echo "2) Worker makine (Kubernetes worker node)"
read -p "Seçiminiz (1/2): " MACHINE_TYPE

if [ "$MACHINE_TYPE" == "1" ]; then
    # Master makine
    NEW_MASTER_IP=$SYSTEM_IP
    NEW_WORKER_IP=$CURRENT_WORKER_IP
    log "Bu sistem Master makine olarak yapılandırılacak."
    log "Master IP: $NEW_MASTER_IP"
    
    # Worker IP'sini kullanıcıya sor
    read -p "Worker makine IP adresini girin [$CURRENT_WORKER_IP]: " WORKER_INPUT
    if [ ! -z "$WORKER_INPUT" ]; then
        NEW_WORKER_IP=$WORKER_INPUT
    fi
    log "Worker IP: $NEW_WORKER_IP"
elif [ "$MACHINE_TYPE" == "2" ]; then
    # Worker makine
    NEW_WORKER_IP=$SYSTEM_IP
    NEW_MASTER_IP=$CURRENT_MASTER_IP
    log "Bu sistem Worker makine olarak yapılandırılacak."
    log "Worker IP: $NEW_WORKER_IP"
    
    # Master IP'sini kullanıcıya sor
    read -p "Master makine IP adresini girin [$CURRENT_MASTER_IP]: " MASTER_INPUT
    if [ ! -z "$MASTER_INPUT" ]; then
        NEW_MASTER_IP=$MASTER_INPUT
    fi
    log "Master IP: $NEW_MASTER_IP"
else
    error "Geçersiz seçim. Script sonlandırılıyor."
    exit 1
fi

# Scriptlerde IP değişikliği yap
update_file_ips() {
    local file=$1
    local old_master_ip=$2
    local new_master_ip=$3
    local old_worker_ip=$4
    local new_worker_ip=$5
    
    if [ -f "$file" ]; then
        log "$file dosyasında IP adresleri güncelleniyor..."
        
        # İşletim sistemini tespit et
        OS_TYPE=$(uname)
        
        # Mac OS X için sed komutu farklı çalışır
        if [ "$OS_TYPE" == "Darwin" ]; then
            # Mac OS X için sed komutu
            sed -i '' "s/MASTER_IP=\"$old_master_ip\"/MASTER_IP=\"$new_master_ip\"/g" "$file"
            sed -i '' "s/WORKER_IP=\"$old_worker_ip\"/WORKER_IP=\"$new_worker_ip\"/g" "$file"
            
            # Diğer olası IP referanslarını güncelle
            sed -i '' "s/$old_master_ip/$new_master_ip/g" "$file"
            sed -i '' "s/$old_worker_ip/$new_worker_ip/g" "$file"
        else
            # Linux için sed komutu
            sed -i "s/MASTER_IP=\"$old_master_ip\"/MASTER_IP=\"$new_master_ip\"/g" "$file"
            sed -i "s/WORKER_IP=\"$old_worker_ip\"/WORKER_IP=\"$new_worker_ip\"/g" "$file"
            
            # Diğer olası IP referanslarını güncelle
            sed -i "s/$old_master_ip/$new_master_ip/g" "$file"
            sed -i "s/$old_worker_ip/$new_worker_ip/g" "$file"
        fi
        
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
        
        # İşletim sistemini tespit et
        OS_TYPE=$(uname)
        
        # Mac OS X için sed komutu farklı çalışır
        if [ "$OS_TYPE" == "Darwin" ]; then
            # Mac OS X için sed komutu
            sed -i '' "s/$old_master_ip/$new_master_ip/g" "$file"
            sed -i '' "s/$old_worker_ip/$new_worker_ip/g" "$file"
        else
            # Linux için sed komutu
            sed -i "s/$old_master_ip/$new_master_ip/g" "$file"
            sed -i "s/$old_worker_ip/$new_worker_ip/g" "$file"
        fi
        
        log "$file dosyasında IP adresleri güncellendi."
    else
        warn "$file dosyası bulunamadı, atlanıyor."
    fi
}

# IP adreslerini güncelle
update_file_ips "$MASTER_SCRIPT" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"
update_file_ips "$WORKER_SCRIPT" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"
update_readme "$README_FILE" "$CURRENT_MASTER_IP" "$NEW_MASTER_IP" "$CURRENT_WORKER_IP" "$NEW_WORKER_IP"

# Scriptleri çalıştırılabilir yap
chmod +x "$MASTER_SCRIPT" "$WORKER_SCRIPT"

log "IP güncelleme işlemi tamamlandı!"
log "Yeni Master IP: $NEW_MASTER_IP"
log "Yeni Worker IP: $NEW_WORKER_IP"
log ""

# Uygun scripti çalıştırma talimatları
if [ "$MACHINE_TYPE" == "1" ]; then
    log "Master kurulum scriptini şu şekilde çalıştırabilirsiniz:"
    log "sudo $MASTER_SCRIPT"
else
    log "Worker kurulum scriptini şu şekilde çalıştırabilirsiniz:"
    log "sudo $WORKER_SCRIPT"
fi 