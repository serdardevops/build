#!/bin/bash

# DevOps Ortamı Test Scripti
# Kubernetes, Jenkins, SonarQube, ArgoCD ve diğer bileşenleri test eder ve şifreleri görüntüler

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonksiyonlar
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

header() {
    echo -e "\n${BLUE}===== $1 =====${NC}\n"
}

# IP adresleri
MASTER_IP="192.168.64.42"
WORKER_IP="192.168.1.138"

# Makine türünü kontrol et
check_machine_type() {
    header "Makine Türü Kontrolü"
    
    hostname=$(hostname)
    if [[ "$hostname" == "master" ]]; then
        log "Bu makine master node'dur."
        IS_MASTER=true
    elif [[ "$hostname" == "worker" ]]; then
        log "Bu makine worker node'dur."
        IS_MASTER=false
    else
        warn "Bu makine ne master ne de worker olarak tanımlanmış. Hostname: $hostname"
        
        # IP adresine göre tahmini makine türü
        local_ip=$(hostname -I | awk '{print $1}')
        if [[ "$local_ip" == "$MASTER_IP" ]]; then
            log "IP adresine göre master olarak değerlendirildi."
            IS_MASTER=true
        elif [[ "$local_ip" == "$WORKER_IP" ]]; then
            log "IP adresine göre worker olarak değerlendirildi."
            IS_MASTER=false
        else
            warn "Makine türü belirlenemedi. Tüm testler yapılacak."
            IS_MASTER=true
        fi
    fi
}

# Kubernetes testi
test_kubernetes() {
    header "Kubernetes Testi"
    
    # Kubectl yapılandırmasını kontrol et
    log "Kubectl yapılandırması kontrol ediliyor..."
    log "KUBECONFIG değişkeni: ${KUBECONFIG:-'Tanımlı değil'}"
    log "Kubeconfig dosyası konumu:"
    kubectl config view --minify | grep server || echo "Server bilgisi bulunamadı"
    
    # Kubernetes bağlantısını test et
    log "Kubernetes API sunucusuna bağlantı test ediliyor..."
    if kubectl cluster-info 2>/dev/null | head -5; then
        log "Kubernetes cluster'a başarıyla bağlandı"
    else
        error "Kubernetes cluster'a bağlanılamadı!"
        log "Cluster info detayları:"
        kubectl cluster-info 2>&1 | head -10
        
        log "Kubeconfig dosyası içeriği kontrol ediliyor:"
        if [ -f ~/.kube/config ]; then
            log "~/.kube/config dosyası mevcut"
            grep -E "(server|certificate-authority)" ~/.kube/config || echo "Server veya CA bilgisi bulunamadı"
        else
            warn "~/.kube/config dosyası bulunamadı!"
        fi
        
        if [ -f /etc/kubernetes/admin.conf ]; then
            log "/etc/kubernetes/admin.conf dosyası mevcut"
            log "KUBECONFIG ortam değişkenini ayarlamayı deneyin:"
            log "export KUBECONFIG=/etc/kubernetes/admin.conf"
        else
            warn "/etc/kubernetes/admin.conf dosyası bulunamadı!"
        fi
        
        return 1
    fi
    
    # Kubernetes versiyonu
    log "Kubernetes client versiyonu kontrol ediliyor..."
    kubectl version --client=true --output=json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4 || echo "Client version bilgisi alınamadı"
    
    log "Kubernetes server versiyonu kontrol ediliyor..."
    kubectl version --output=json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4 || echo "Server version bilgisi alınamadı (cluster erişimi gerekebilir)"
    
    # Node'ları listele
    log "Kubernetes node'ları listeleniyor..."
    kubectl get nodes -o wide || { error "Node'lar listelenemedi!"; return 1; }
    
    # Namespace'leri listele
    log "Kubernetes namespace'leri listeleniyor..."
    kubectl get namespaces || { error "Namespace'ler listelenemedi!"; return 1; }
    
    # Pod'ları listele
    log "Kubernetes pod'ları listeleniyor..."
    kubectl get pods --all-namespaces || { error "Pod'lar listelenemedi!"; return 1; }
    
    # Servis'leri listele
    log "Kubernetes servisleri listeleniyor..."
    kubectl get services --all-namespaces || { error "Servisler listelenemedi!"; return 1; }
    
    # Deployment'ları listele
    log "Kubernetes deployment'ları listeleniyor..."
    kubectl get deployments --all-namespaces || { error "Deployment'lar listelenemedi!"; return 1; }
}

# Docker testi
test_docker() {
    header "Docker Testi"
    
    # Docker versiyonu
    log "Docker versiyonu kontrol ediliyor..."
    docker version
    
    # Çalışan container'ları listele
    log "Çalışan container'lar listeleniyor..."
    docker ps
    
    # Tüm container'ları listele
    log "Tüm container'lar listeleniyor..."
    docker ps -a
    
    # Docker image'larını listele
    log "Docker image'ları listeleniyor..."
    docker images
}

# Jenkins testi
test_jenkins() {
    if [ "$IS_MASTER" = false ]; then
        warn "Bu worker makinedir. Jenkins testi atlanıyor."
        return
    fi
    
    header "Jenkins Testi"
    
    # Jenkins çalışıyor mu?
    log "Jenkins servis durumu kontrol ediliyor..."
    systemctl status jenkins | grep Active
    
    # Jenkins portu açık mı?
    log "Jenkins port kontrolü yapılıyor..."
    nc -zv localhost 8080 || warn "Jenkins portu (8080) açık değil!"
    
    # Jenkins şifresini görüntüle
    log "Jenkins şifresi kontrol ediliyor..."
    if [ -f /home/ubuntu/jenkins-password.txt ]; then
        log "Jenkins admin şifresi:"
        cat /home/ubuntu/jenkins-password.txt
    else
        warn "Jenkins şifre dosyası bulunamadı. İlk kurulum şifresi görüntüleniyor..."
        if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
            log "Jenkins ilk kurulum admin şifresi:"
            cat /var/lib/jenkins/secrets/initialAdminPassword
        else
            error "Jenkins şifresi bulunamadı!"
        fi
    fi
    
    # Jenkins URL'i görüntüle
    log "Jenkins URL: http://$MASTER_IP:8080"
}

# SonarQube testi
test_sonarqube() {
    if [ "$IS_MASTER" = false ]; then
        warn "Bu worker makinedir. SonarQube testi atlanıyor."
        return
    fi
    
    header "SonarQube Testi"
    
    # SonarQube çalışıyor mu?
    log "SonarQube servis durumu kontrol ediliyor..."
    systemctl status sonarqube | grep Active || warn "SonarQube servisi çalışmıyor veya bulunamadı!"
    
    # SonarQube portu açık mı?
    log "SonarQube port kontrolü yapılıyor..."
    nc -zv localhost 9000 || warn "SonarQube portu (9000) açık değil!"
    
    # SonarQube giriş bilgileri
    log "SonarQube giriş bilgileri:"
    log "URL: http://$MASTER_IP:9000"
    log "Kullanıcı adı: admin"
    log "Şifre: admin (ilk girişte değiştirmeniz istenecek)"
}

# ArgoCD testi
test_argocd() {
    if [ "$IS_MASTER" = false ]; then
        warn "Bu worker makinedir. ArgoCD testi atlanıyor."
        return
    fi
    
    header "ArgoCD Testi"
    
    # ArgoCD namespace var mı?
    log "ArgoCD namespace kontrol ediliyor..."
    kubectl get namespace argocd || { error "ArgoCD namespace bulunamadı!"; return; }
    
    # ArgoCD pod'ları çalışıyor mu?
    log "ArgoCD pod'ları kontrol ediliyor..."
    kubectl get pods -n argocd
    
    # ArgoCD servisi kontrol et
    log "ArgoCD servisi kontrol ediliyor..."
    kubectl get svc -n argocd
    
    # ArgoCD port kontrolü
    log "ArgoCD port kontrolü yapılıyor..."
    nc -zv $MASTER_IP 30080 || warn "ArgoCD portu (30080) açık değil!"
    
    # ArgoCD admin şifresi
    log "ArgoCD admin şifresi kontrol ediliyor..."
    if [ -f /home/ubuntu/argocd-password.txt ]; then
        log "ArgoCD admin şifresi:"
        cat /home/ubuntu/argocd-password.txt
    else
        log "ArgoCD şifre dosyası bulunamadı. Secret'ten alınmaya çalışılıyor..."
        ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
        if [ -n "$ARGOCD_PASS" ]; then
            log "ArgoCD admin şifresi: $ARGOCD_PASS"
        else
            error "ArgoCD şifresi bulunamadı! ArgoCD secret'ları kontrol edilecek..."
            kubectl get secrets -n argocd
        fi
    fi
    
    # ArgoCD URL'i görüntüle
    log "ArgoCD URL: http://$MASTER_IP:30080"
    log "ArgoCD kullanıcı adı: admin"
}

# Kubernetes Dashboard testi
test_k8s_dashboard() {
    if [ "$IS_MASTER" = false ]; then
        warn "Bu worker makinedir. Kubernetes Dashboard testi atlanıyor."
        return
    fi
    
    header "Kubernetes Dashboard Testi"
    
    # Dashboard namespace var mı?
    log "Kubernetes Dashboard namespace kontrol ediliyor..."
    kubectl get namespace kubernetes-dashboard || { error "Kubernetes Dashboard namespace bulunamadı!"; return; }
    
    # Dashboard pod'ları çalışıyor mu?
    log "Kubernetes Dashboard pod'ları kontrol ediliyor..."
    kubectl get pods -n kubernetes-dashboard
    
    # Dashboard servisi kontrol et
    log "Kubernetes Dashboard servisi kontrol ediliyor..."
    kubectl get svc -n kubernetes-dashboard
    
    # Dashboard port kontrolü
    log "Kubernetes Dashboard port kontrolü yapılıyor..."
    nc -zv $MASTER_IP 30001 || warn "Kubernetes Dashboard portu (30001) açık değil!"
    
    # Dashboard token'ı
    log "Kubernetes Dashboard token kontrol ediliyor..."
    if [ -f /home/ubuntu/dashboard-token.txt ]; then
        log "Kubernetes Dashboard token:"
        cat /home/ubuntu/dashboard-token.txt
    else
        log "Dashboard token dosyası bulunamadı. Token oluşturuluyor..."
        log "Yeni token:"
        kubectl create token admin-user -n kubernetes-dashboard
    fi
    
    # Dashboard URL'i görüntüle
    log "Kubernetes Dashboard URL: https://$MASTER_IP:30001"
    log "Kubernetes Dashboard token ile giriş yapın."
}

# Worker Node Exporter testi
test_node_exporter() {
    if [ "$IS_MASTER" = true ]; then
        warn "Bu master makinedir. Node Exporter testi atlanıyor."
        return
    fi
    
    header "Node Exporter Testi"
    
    # Node Exporter çalışıyor mu?
    log "Node Exporter servis durumu kontrol ediliyor..."
    systemctl status node_exporter | grep Active
    
    # Node Exporter portu açık mı?
    log "Node Exporter port kontrolü yapılıyor..."
    nc -zv localhost 9100 || warn "Node Exporter portu (9100) açık değil!"
    
    # Node Exporter metriklerini test et
    log "Node Exporter metriklerini kontrol ediliyor..."
    curl -s http://localhost:9100/metrics | head -10
    
    # Node Exporter URL'i görüntüle
    log "Node Exporter metrics URL: http://$WORKER_IP:9100/metrics"
}

# Worker Prometheus testi
test_prometheus() {
    if [ "$IS_MASTER" = true ]; then
        warn "Bu master makinedir. Prometheus testi atlanıyor."
        return
    fi
    
    header "Prometheus Testi"
    
    # Prometheus çalışıyor mu?
    log "Prometheus servis durumu kontrol ediliyor..."
    systemctl status prometheus | grep Active
    
    # Prometheus portu açık mı?
    log "Prometheus port kontrolü yapılıyor..."
    nc -zv localhost 9090 || warn "Prometheus portu (9090) açık değil!"
    
    # Prometheus API test et
    log "Prometheus API kontrol ediliyor..."
    curl -s http://localhost:9090/api/v1/status/targets | head -5
    
    # Prometheus URL'i görüntüle
    log "Prometheus web arayüzü: http://$WORKER_IP:9090"
    log "Prometheus API: http://$WORKER_IP:9090/api/v1/"
}

# Worker Grafana testi
test_grafana() {
    if [ "$IS_MASTER" = true ]; then
        warn "Bu master makinedir. Grafana testi atlanıyor."
        return
    fi
    
    header "Grafana Testi"
    
    # Grafana çalışıyor mu?
    log "Grafana servis durumu kontrol ediliyor..."
    systemctl status grafana-server | grep Active
    
    # Grafana portu açık mı?
    log "Grafana port kontrolü yapılıyor..."
    nc -zv localhost 3000 || warn "Grafana portu (3000) açık değil!"
    
    # Grafana API test et
    log "Grafana API kontrol ediliyor..."
    curl -s http://localhost:3000/api/health || warn "Grafana API erişilemez!"
    
    # Grafana giriş bilgileri
    log "Grafana giriş bilgileri:"
    log "URL: http://$WORKER_IP:3000"
    log "Kullanıcı adı: admin"
    log "Şifre: admin (ilk girişte değiştirmeniz istenecek)"
}

# Nginx örnek test
test_nginx_example() {
    if [ "$IS_MASTER" = false ]; then
        warn "Bu worker makinedir. Nginx örnek testi atlanıyor."
        return
    fi
    
    header "Nginx Örnek Testi"
    
    # Nginx örnek deployment var mı?
    log "Nginx örnek deployment kontrol ediliyor..."
    kubectl get deployment nginx-example || { warn "Nginx örnek deployment bulunamadı!"; return; }
    
    # Nginx örnek pod'ları çalışıyor mu?
    log "Nginx örnek pod'ları kontrol ediliyor..."
    kubectl get pods -l app=nginx-example
    
    # Nginx örnek servisi kontrol et
    log "Nginx örnek servisi kontrol ediliyor..."
    kubectl get svc nginx-example-service
    
    # Nginx örnek port kontrolü
    log "Nginx örnek port kontrolü yapılıyor..."
    nc -zv $MASTER_IP 30090 || warn "Nginx örnek portu (30090) açık değil!"
    
    # Nginx örnek URL'i görüntüle
    log "Nginx örnek URL: http://$MASTER_IP:30090"
}

# Network testi
test_network() {
    header "Network Testi"
    
    # Master'a ping atabilme
    log "Master node'a ping atılıyor..."
    ping -c 3 $MASTER_IP || warn "Master node'a ($MASTER_IP) ping atılamadı!"
    
    # Worker'a ping atabilme
    log "Worker node'a ping atılıyor..."
    ping -c 3 $WORKER_IP || warn "Worker node'a ($WORKER_IP) ping atılamadı!"
    
    # DNS çözümleme
    log "DNS çözümleme testi yapılıyor..."
    ping -c 1 google.com || warn "Internet bağlantısı veya DNS çözümleme sorunu!"
    
    # Firewall durumu
    log "Firewall durumu kontrol ediliyor..."
    ufw status
}

# Cluster özeti
show_cluster_summary() {
    header "Cluster Özeti"
    
    # Kurulan bileşenleri ve URL'leri listele
    log "DevOps Ortamı Erişim Bilgileri:"
    echo -e "${GREEN}------------------------------------------------${NC}"
    echo -e "${GREEN}| Bileşen               | URL                   |${NC}"
    echo -e "${GREEN}------------------------------------------------${NC}"
    echo -e "${GREEN}| Kubernetes API        | https://$MASTER_IP:6443 |${NC}"
    echo -e "${GREEN}| Jenkins               | http://$MASTER_IP:8080  |${NC}"
    echo -e "${GREEN}| SonarQube             | http://$MASTER_IP:9000  |${NC}"
    echo -e "${GREEN}| ArgoCD                | http://$MASTER_IP:30080 |${NC}"
    echo -e "${GREEN}| Kubernetes Dashboard  | https://$MASTER_IP:30001 |${NC}"
    echo -e "${GREEN}| Nginx Örnek           | http://$MASTER_IP:30090 |${NC}"
    echo -e "${GREEN}| Node Exporter (Worker)| http://$WORKER_IP:9100  |${NC}"
    echo -e "${GREEN}| Prometheus (Worker)   | http://$WORKER_IP:9090  |${NC}"
    echo -e "${GREEN}| Grafana (Worker)      | http://$WORKER_IP:3000  |${NC}"
    echo -e "${GREEN}------------------------------------------------${NC}"
    
    # Şifreleri listele
    log "Giriş Bilgileri:"
    echo -e "${YELLOW}---------------------------------------------------------------${NC}"
    echo -e "${YELLOW}| Bileşen               | Kullanıcı Adı | Şifre Dosyası      |${NC}"
    echo -e "${YELLOW}---------------------------------------------------------------${NC}"
    echo -e "${YELLOW}| Jenkins               | admin         | /home/ubuntu/jenkins-password.txt |${NC}"
    echo -e "${YELLOW}| SonarQube             | admin         | admin (ilk girişte değiştirin) |${NC}"
    echo -e "${YELLOW}| ArgoCD                | admin         | /home/ubuntu/argocd-password.txt |${NC}"
    echo -e "${YELLOW}| Kubernetes Dashboard  | -             | /home/ubuntu/dashboard-token.txt |${NC}"
    echo -e "${YELLOW}| Grafana (Worker)      | admin         | admin (ilk girişte değiştirin) |${NC}"
    echo -e "${YELLOW}---------------------------------------------------------------${NC}"
    
    # Cluster bilgileri dosyasını görüntüle
    if [ -f /home/ubuntu/cluster-info.txt ]; then
        log "Cluster bilgileri dosyası mevcut:"
        cat /home/ubuntu/cluster-info.txt
    fi
}

# Yardımcı araçların yüklü olup olmadığını kontrol et
check_dependencies() {
    header "Bağımlılık Kontrolü"
    
    # Gerekli araçları kontrol et
    commands=("kubectl" "docker" "nc" "curl" "ping")
    for cmd in "${commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            log "$cmd yüklü."
        else
            warn "$cmd yüklü değil. Bazı testler çalışmayabilir."
        fi
    done
}

# Ana fonksiyon
main() {
    header "DevOps Ortamı Test Scripti"
    
    # Bağımlılıkları kontrol et
    check_dependencies
    
    # Makine türünü kontrol et
    check_machine_type
    
    # Network testleri
    test_network
    
    # Kubernetes testi
    test_kubernetes
    
    # Docker testi
    test_docker
    
    # Jenkins testi (sadece master'da)
    test_jenkins
    
    # SonarQube testi (sadece master'da)
    test_sonarqube
    
    # ArgoCD testi (sadece master'da)
    test_argocd
    
    # Kubernetes Dashboard testi (sadece master'da)
    test_k8s_dashboard
    
    # Nginx örnek testi (sadece master'da)
    test_nginx_example
    
    # Node Exporter testi (sadece worker'da)
    test_node_exporter
    
    # Prometheus testi (sadece worker'da)
    test_prometheus
    
    # Grafana testi (sadece worker'da)
    test_grafana
    
    # Cluster özeti
    show_cluster_summary
    
    header "Test Tamamlandı"
    log "Tüm testler başarıyla tamamlandı."
}

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkileri gerektirmektedir. 'sudo ./test-devops.sh' komutunu kullanın."
    exit 1
fi

# Scripti çalıştır
main "$@" 