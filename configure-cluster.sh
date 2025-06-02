#!/bin/bash

# Kubernetes Cluster Yapılandırma Scripti
# Master node'da çalıştırılacak ek yapılandırmalar

set -e

# Renkler
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

export KUBECONFIG=/etc/kubernetes/admin.conf

# Makine bilgileri
MASTER_IP="192.168.1.137"
WORKER_IP="192.168.1.138"

# Cluster durumunu kontrol et
check_cluster_status() {
    log "Cluster durumu kontrol ediliyor..."
    
    # Node'ların hazır olmasını bekle
    while [[ $(kubectl get nodes --no-headers | grep -c "Ready") -lt 2 ]]; do
        log "Tüm node'ların hazır olması bekleniyor..."
        kubectl get nodes
        sleep 30
    done
    
    log "Tüm node'lar hazır!"
    kubectl get nodes
}

# Ingress Controller kurulumu
install_ingress_controller() {
    log "NGINX Ingress Controller kuruluyor..."
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
    
    # Ingress Controller'ın hazır olmasını bekle
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log "NGINX Ingress Controller kuruldu"
}

# Metrics Server kurulumu
install_metrics_server() {
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
    
    log "Metrics Server kuruldu"
}

# Storage Class oluştur
create_storage_class() {
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
    
    log "Local Storage Class oluşturuldu"
}

# Example deployments
deploy_examples() {
    log "Örnek deployment'lar oluşturuluyor..."
    
    # Nginx örnek deployment
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
    
    log "Nginx örnek deployment oluşturuldu - Port: 30090"
}

# Network policies oluştur
create_network_policies() {
    log "Varsayılan network policy'ler oluşturuluyor..."
    
    # Default deny all policy
    cat > /tmp/default-deny.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
    
    # Allow DNS policy
    cat > /tmp/allow-dns.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
    
    # kubectl apply -f /tmp/default-deny.yaml
    # kubectl apply -f /tmp/allow-dns.yaml
    
    log "Network policy dosyaları hazırlandı (aktif değil)"
}

# Resource quotas oluştur
create_resource_quotas() {
    log "Resource quota'lar oluşturuluyor..."
    
    # Default namespace için quota
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
    
    log "Resource quota'lar oluşturuldu"
}

# Cluster bilgilerini kaydet
save_cluster_info() {
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

Jenkins: http://192.168.1.137:8080
- Admin şifresi: /home/ubuntu/jenkins-password.txt

SonarQube: http://192.168.1.137:9000
- Varsayılan: admin/admin

ArgoCD: http://192.168.1.137:30080
- Kullanıcı: admin
- Şifre: /home/ubuntu/argocd-password.txt

Kubernetes Dashboard: https://192.168.1.137:30001
- Token: /home/ubuntu/dashboard-token.txt

Nginx Örnek: http://192.168.1.137:30090

=== KUBECTL KOMUTLARI ===

# Cluster durumunu kontrol et
kubectl get nodes
kubectl get pods --all-namespaces

# Log'ları görüntüle
kubectl logs -f deployment/nginx-example

# Pod'lara erişim
kubectl exec -it <pod-name> -- /bin/bash

=== MONİTORİNG ===

Node Exporter (Worker): http://192.168.1.138:9100/metrics

EOF
    
    chown ubuntu:ubuntu /home/ubuntu/cluster-info.txt
    
    log "Cluster bilgileri /home/ubuntu/cluster-info.txt dosyasına kaydedildi"
}

# Health check
health_check() {
    log "Cluster health check yapılıyor..."
    
    # API server health
    kubectl get --raw='/readyz?verbose'
    
    # Component status
    kubectl get componentstatuses
    
    # Pod status in all namespaces
    kubectl get pods --all-namespaces | grep -v Running | grep -v Completed || echo "Tüm pod'lar çalışıyor"
    
    log "Health check tamamlandı"
}

# Ana fonksiyon
main() {
    log "Cluster yapılandırması başlıyor..."
    
    # Node'ların hazır olmasını bekle
    sleep 60
    
    check_cluster_status
    install_metrics_server
    install_ingress_controller
    create_storage_class
    deploy_examples
    create_network_policies
    create_resource_quotas
    save_cluster_info
    health_check
    
    log "Cluster yapılandırması tamamlandı!"
    
    # Final cluster durumu
    echo ""
    log "=== FİNAL CLUSTER DURUMU ==="
    kubectl get nodes
    kubectl get pods --all-namespaces
    kubectl get services --all-namespaces
}

main "$@" 