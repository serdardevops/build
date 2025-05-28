#!/bin/bash

# SonarQube Güncelleme Scripti
# Bu script, SonarQube'u en son sürüme (25.5.0.107428) günceller
# Kullanım: sudo ./sonarqube-update.sh

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

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkileri gerektirmektedir. 'sudo ./sonarqube-update.sh' komutunu kullanın."
    exit 1
fi

# --- Ayarlar ---
SONAR_VERSION="25.5.0.107428"
SONAR_USER="sonar"
SONAR_HOME="/opt/sonarqube"
SONAR_ZIP="sonarqube-$SONAR_VERSION.zip"
SONAR_DOWNLOAD_URL="https://binaries.sonarsource.com/Distribution/sonarqube/$SONAR_ZIP"
SONAR_SERVICE_FILE="/etc/systemd/system/sonarqube.service"
ARCH=$(dpkg --print-architecture)

# --- Başlangıç ---
log "SonarQube $SONAR_VERSION sürümüne güncelleniyor..."

# Yedekleme
if [ -d "$SONAR_HOME" ]; then
    log "Mevcut SonarQube yapılandırması yedekleniyor..."
    BACKUP_DIR="/opt/sonarqube-backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    # Yalnızca önemli dizinleri yedekle
    if [ -d "$SONAR_HOME/conf" ]; then
        cp -r $SONAR_HOME/conf $BACKUP_DIR/
        log "Yapılandırma dosyaları $BACKUP_DIR/conf dizinine yedeklendi."
    fi
    
    if [ -d "$SONAR_HOME/extensions" ]; then
        cp -r $SONAR_HOME/extensions $BACKUP_DIR/
        log "Eklentiler $BACKUP_DIR/extensions dizinine yedeklendi."
    fi
    
    if [ -d "$SONAR_HOME/data" ]; then
        cp -r $SONAR_HOME/data $BACKUP_DIR/
        log "Veri dosyaları $BACKUP_DIR/data dizinine yedeklendi."
    fi
    
    # Servis dosyasını da yedekle
    if [ -f "$SONAR_SERVICE_FILE" ]; then
        cp $SONAR_SERVICE_FILE $BACKUP_DIR/
        log "Servis dosyası $BACKUP_DIR/ dizinine yedeklendi."
    fi
fi

log "SonarQube tam kaldırılıyor (varsa)..."
systemctl stop sonarqube.service 2>/dev/null || true
systemctl disable sonarqube.service 2>/dev/null || true
rm -f $SONAR_SERVICE_FILE
systemctl daemon-reload

log "Gerekli paketler kuruluyor..."
apt-get update
apt-get install -y openjdk-21-jdk wget unzip

# SonarQube kullanıcısı mevcut değilse oluştur
if ! id "$SONAR_USER" &>/dev/null; then
    log "'$SONAR_USER' kullanıcısı oluşturuluyor..."
    useradd -r -m -s /bin/bash $SONAR_USER
fi

log "/tmp dizinine geçiliyor ve SonarQube indiriliyor..."
cd /tmp || { error "Hata: /tmp dizinine geçilemedi!"; exit 1; }
wget -c $SONAR_DOWNLOAD_URL -O $SONAR_ZIP || { error "SonarQube indirilemedi!"; exit 1; }

log "SonarQube arşivi açılıyor..."
rm -rf $SONAR_HOME
unzip -q -o $SONAR_ZIP -d /opt || { error "SonarQube arşivi açılamadı!"; exit 1; }
mv /opt/sonarqube-$SONAR_VERSION $SONAR_HOME || { error "SonarQube dizini taşınamadı!"; exit 1; }

# Yedeklenen yapılandırma dosyalarını geri yükle
if [ -d "$BACKUP_DIR/conf" ]; then
    log "Yedeklenen yapılandırma dosyaları geri yükleniyor..."
    # sonar.properties dosyasını ayrı olarak işle
    if [ -f "$BACKUP_DIR/conf/sonar.properties" ]; then
        cp $BACKUP_DIR/conf/sonar.properties $SONAR_HOME/conf/
    fi
    
    # wrapper.conf dosyasını Java 21 için güncelle
    if [ "$ARCH" == "arm64" ]; then
        echo "wrapper.java.command=/usr/lib/jvm/java-21-openjdk-arm64/bin/java" > $SONAR_HOME/conf/wrapper.conf
    else
        echo "wrapper.java.command=/usr/lib/jvm/java-21-openjdk-amd64/bin/java" > $SONAR_HOME/conf/wrapper.conf
    fi
else
    # Yapılandırma dosyası yoksa yeni oluştur
    log "SonarQube yapılandırması oluşturuluyor..."
    cat > $SONAR_HOME/conf/sonar.properties << EOF
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
EOF
    
    # Java 21 yapılandırması
    if [ "$ARCH" == "arm64" ]; then
        mkdir -p $SONAR_HOME/conf/
        echo "wrapper.java.command=/usr/lib/jvm/java-21-openjdk-arm64/bin/java" > $SONAR_HOME/conf/wrapper.conf
    else
        mkdir -p $SONAR_HOME/conf/
        echo "wrapper.java.command=/usr/lib/jvm/java-21-openjdk-amd64/bin/java" > $SONAR_HOME/conf/wrapper.conf
    fi
fi

# Eklentileri geri yükle
if [ -d "$BACKUP_DIR/extensions" ]; then
    log "Yedeklenen eklentiler geri yükleniyor..."
    cp -r $BACKUP_DIR/extensions/* $SONAR_HOME/extensions/
fi

# ARM64 mimarisi için özel ayarlar
if [ "$ARCH" == "arm64" ]; then
    log "ARM64 mimarisi için başlatma scriptini düzenleniyor..."
    # SonarQube başlatma scriptini ARM için düzenle
    if [ ! -d "$SONAR_HOME/bin/linux-arm64" ]; then
        mkdir -p $SONAR_HOME/bin/linux-arm64
        cp $SONAR_HOME/bin/linux-x86-64/sonar.sh $SONAR_HOME/bin/linux-arm64/
        chmod +x $SONAR_HOME/bin/linux-arm64/sonar.sh
    fi
fi

log "SonarQube systemd servisi oluşturuluyor..."
cat > $SONAR_SERVICE_FILE << EOF
[Unit]
Description=SonarQube
After=network.target

[Service]
Type=forking
User=$SONAR_USER
Group=$SONAR_USER
ExecStart=$SONAR_HOME/bin/linux-$ARCH/sonar.sh start
ExecStop=$SONAR_HOME/bin/linux-$ARCH/sonar.sh stop
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
TimeoutStartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Sistem limitleri ayarla
log "Sistem limitleri yapılandırılıyor..."
if ! grep -q "vm.max_map_count=524288" /etc/sysctl.conf; then
    echo "vm.max_map_count=524288" >> /etc/sysctl.conf
fi
if ! grep -q "fs.file-max=131072" /etc/sysctl.conf; then
    echo "fs.file-max=131072" >> /etc/sysctl.conf
fi
sysctl -p

# İzinleri ayarla
log "İzinler ayarlanıyor..."
chown -R $SONAR_USER:$SONAR_USER $SONAR_HOME

log "Systemd yeniden yükleniyor ve SonarQube başlatılıyor..."
systemctl daemon-reload
systemctl enable sonarqube.service
systemctl start sonarqube.service

log "SonarQube servisi durumu:"
systemctl status sonarqube.service --no-pager

log "SonarQube $SONAR_VERSION sürümü başarıyla güncellendi!"
log "SonarQube web arayüzüne http://$(hostname -I | awk '{print $1}'):9000 adresinden erişebilirsiniz."
log "Varsayılan giriş bilgileri: admin / admin" 