# DevOps Araçları Otomatik Kurulum Scripti

Bu script, Multipass üzerinde çalışan 2 Ubuntu 24.04 Noble makinesine kapsamlı bir DevOps ortamı kurar.

## 📋 Kurulacak Araçlar

### Master Makine (192.168.1.131)
- **Docker** - Container platformu
- **Kubernetes Master** - Container orkestrasyon master node (v1.32)
- **Jenkins** - CI/CD automation server (JDK 21)
- **SonarQube** - Code quality platform
- **ArgoCD** - GitOps deployment tool
- **Helm** - Kubernetes package manager
- **Kubernetes Dashboard** - Web UI for Kubernetes

### Worker Makine (192.168.1.117)
- **Docker** - Container platformu
- **Kubernetes Worker** - Container orkestrasyon worker node (v1.32)
- **Node Exporter** - Prometheus monitoring agent

## 🚀 Hızlı Başlangıç

### Önkoşullar
- Multipass kurulu ve çalışır durumda
- 2 adet Ubuntu 24.04 LTS makinesi (master ve worker)
- SSH erişimi aktif

### Kurulum Adımları

1. **Scriptleri çalıştırılabilir yap:**
   ```bash
   chmod +x *.sh
   ```

2. **Ana kurulum scriptini çalıştır:**
   ```bash
   ./setup-devops.sh
   ```

3. **Kurulum sürecini izle:**
   - Master makine kurulumu ~20-30 dakika
   - Worker makine kurulumu ~10-15 dakika
   - Cluster yapılandırması ~5-10 dakika

## 🔧 Manuel Kurulum

Eğer otomatik kurulum yapamıyorsanız, scriptleri manuel olarak çalıştırabilirsiniz:

### Master Makinesinde:
```bash
# Master makinesine bağlan
multipass shell master

# Scripti kopyala ve çalıştır
sudo ./master-setup.sh
```

### Worker Makinesinde:
```bash
# Worker makinesine bağlan
multipass shell worker

# Scripti kopyala ve çalıştır
sudo ./worker-setup.sh
```

### Cluster Yapılandırması:
```bash
# Master makinesinde
sudo ./configure-cluster.sh
```

## 🌐 Erişim Adresleri

Kurulum tamamlandığında aşağıdaki servislere erişebilirsiniz:

| Servis | URL | Kullanıcı | Şifre Lokasyonu |
|--------|-----|-----------|----------------|
| Jenkins | http://192.168.1.131:8080 | admin | `/home/ubuntu/jenkins-password.txt` |
| SonarQube | http://192.168.1.131:9000 | admin | admin |
| ArgoCD | http://192.168.1.131:30080 | admin | `/home/ubuntu/argocd-password.txt` |
| Kubernetes Dashboard | https://192.168.1.131:30001 | - | `/home/ubuntu/dashboard-token.txt` |
| Nginx Örnek | http://192.168.1.131:30090 | - | - |
| Node Exporter | http://192.168.1.117:9100/metrics | - | - |

## 🆕 Ubuntu 24.04 Noble Özellikleri

### Güncellenen Bileşenler
- **Kubernetes v1.32** - En son kararlı sürüm
- **JDK 21** - Jenkins için LTS Java sürümü
- **Node Exporter v1.8.2** - Güncel monitoring agent
- **Kubernetes Repository** - Noble uyumlu stable repository

### Uyumluluk
- Ubuntu 24.04 Noble Numbat için optimize edilmiş
- Kubernetes stable repository kullanımı
- Dağıtımdan bağımsız paket yönetimi

## 🔒 Güvenlik Yapılandırması

### Firewall Kuralları
- **SSH (22)** - Her iki makinede açık
- **Kubernetes API (6443)** - Master'da açık
- **Jenkins (8080)** - Master'da açık
- **SonarQube (9000)** - Master'da açık
- **ArgoCD (30080)** - Master'da açık
- **NodePort Aralığı (30000-32767)** - Her iki makinede açık
- **Kubelet (10250)** - Her iki makinede açık
- **CNI Portları (8285, 8472 UDP)** - Her iki makinede açık

### Network Policies
- Varsayılan network policy dosyaları hazırlanır (aktif değil)
- Gerektiğinde `kubectl apply` ile aktifleştirilebilir

## 📊 Monitoring

### Node Monitoring
- Worker makinesinde Node Exporter çalışır
- Prometheus ile entegre edilebilir
- Metrics: http://192.168.1.117:9100/metrics

### Kubernetes Monitoring
- Metrics Server kurulu
- `kubectl top nodes` ve `kubectl top pods` komutları çalışır
- Kubernetes Dashboard ile görsel monitoring

## 🛠️ Maintenance

### Log Yönetimi
- Docker log rotation otomatik yapılandırılmış
- Kubernetes log temizleme cron job'u kurulu
- Günlük log temizleme çalışır

### Resource Management
- Resource quota'lar tanımlı
- CPU ve memory limitleri ayarlanmış
- Storage class tanımlı

## 📝 Kullanım Örnekleri

### Kubernetes Cluster Yönetimi
```bash
# Cluster durumunu kontrol et
kubectl get nodes

# Pod'ları listele
kubectl get pods --all-namespaces

# Servis durumunu kontrol et
kubectl get services

# Log'ları görüntüle
kubectl logs -f deployment/nginx-example

# Dashboard token'ı al
cat /home/ubuntu/dashboard-token.txt
```

### Jenkins Pipeline Örneği
```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                echo 'Building...'
            }
        }
        stage('Test') {
            steps {
                echo 'Testing...'
            }
        }
        stage('Deploy') {
            steps {
                echo 'Deploying...'
            }
        }
    }
}
```

### ArgoCD Uygulama Dağıtımı
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-repo/app
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## 🔍 Troubleshooting

### Genel Kontroller
```bash
# Sistem durumu
systemctl status docker
systemctl status kubelet

# Log'ları kontrol et
journalctl -u docker -f
journalctl -u kubelet -f

# Disk kullanımı
df -h
docker system df
```

### Kubernetes Sorunları
```bash
# Cluster health check
kubectl get componentstatuses

# Node durumu detaylı
kubectl describe nodes

# Pod sorunları
kubectl describe pod <pod-name>

# Event'leri kontrol et
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Network Sorunları
```bash
# Firewall durumu
ufw status
iptables -L

# Port dinleme kontrolü
netstat -tlnp

# CNI durumu
kubectl get pods -n kube-system | grep flannel
```

## 📚 Ek Kaynaklar

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [SonarQube Documentation](https://docs.sonarqube.org/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Katkıda Bulunma

Bu script'i geliştirmek için:
1. Fork yapın
2. Feature branch oluşturun
3. Değişikliklerinizi commit edin
4. Pull request gönderin

## 📄 Lisans

Bu proje MIT lisansı altında yayınlanmıştır.

---

**Not:** Bu script production kullanımı için ek güvenlik yapılandırmaları gerektirebilir. Development ve test ortamları için optimize edilmiştir. 