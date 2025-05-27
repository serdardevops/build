# DevOps Ortamı Kurulum Scriptleri

Bu klasör, Kubernetes ve DevOps araçlarının kurulumu için kullanılan bağımsız scriptleri içerir. Bu scriptler, master ve worker makineler için ayrı ayrı tasarlanmıştır ve herhangi bir SSH bağlantısı gerektirmeden, her makinede ayrı olarak çalıştırılabilir.

## Sistem Gereksinimleri

- **Master Makine**: Ubuntu 24.04 LTS, en az 4GB RAM, 2 CPU
- **Worker Makine**: Ubuntu 24.04 LTS, en az 2GB RAM, 1 CPU
- Her iki makinede de root erişimi gereklidir

## IP Bilgileri

Bu scriptler aşağıdaki IP adresleri için yapılandırılmıştır:

- **Master IP**: 192.168.1.137
- **Worker IP**: 192.168.1.138

> **Not**: Farklı IP adresleriniz varsa, her iki scriptteki `MASTER_IP` ve `WORKER_IP` değişkenlerini düzenlemeniz gerekir.

## Kurulum Adımları

### 1. Master Makine Kurulumu

Master makinede aşağıdaki adımları izleyin:

```bash
# Scripti çalıştırılabilir yapın
chmod +x master-kurulum.sh

# Kurulumu başlatın
sudo ./master-kurulum.sh
```

Kurulum tamamlandığında aşağıdaki servislere erişebilirsiniz:

- Jenkins: http://192.168.1.137:8080
- SonarQube: http://192.168.1.137:9000
- ArgoCD: http://192.168.1.137:30080
- Kubernetes Dashboard: https://192.168.1.137:30001
- Nginx Örnek: http://192.168.1.137:30090

### 2. Worker Makine Kurulumu

Worker makinede aşağıdaki adımları izleyin:

```bash
# Scripti çalıştırılabilir yapın
chmod +x worker-kurulum.sh

# Kurulumu başlatın
sudo ./worker-kurulum.sh
```

### 3. Worker Makineyi Cluster'a Ekleyin

Worker kurulumu tamamlandıktan sonra, worker'ı Kubernetes cluster'a eklemek için:

```bash
# Master makinede join komutunu alın
cat /home/ubuntu/join-command.txt

# Bu komutu worker makinede çalıştırın
sudo kubeadm join 192.168.1.137:6443 --token XXXX --discovery-token-ca-cert-hash XXXX
```

Alternatif olarak, master makinede şu komutu çalıştırabilirsiniz:

```bash
cat /home/ubuntu/join-command.txt | ssh ubuntu@192.168.1.138 "sudo bash"
```

## Hostname Çözümlemesi

Her iki script de hostname çözümlemesi için `/etc/hosts` dosyasını otomatik olarak günceller. Eğer hostname çözümlemesi ile ilgili sorun yaşarsanız, her iki makinede de `/etc/hosts` dosyasında şu girdilerin olduğundan emin olun:

```
192.168.1.137 master
192.168.1.138 worker
```

## Kurulu Bileşenler

### Master Makinede:
- Docker
- Kubernetes Master
- Flannel CNI
- Jenkins
- SonarQube
- ArgoCD
- Helm
- Kubernetes Dashboard
- Metrics Server

### Worker Makinede:
- Docker
- Kubernetes Worker Node
- Node Exporter (Port 9100)

## Erişim Bilgileri

- Jenkins: Admin şifresi `/home/ubuntu/jenkins-password.txt` dosyasında
- SonarQube: Kullanıcı adı `admin`, şifre `admin`
- ArgoCD: Admin şifresi `/home/ubuntu/argocd-password.txt` dosyasında
- Kubernetes Dashboard: Token `/home/ubuntu/dashboard-token.txt` dosyasında

## Sorun Giderme

Eğer kurulum sırasında bir sorunla karşılaşırsanız:

1. Her iki makinede `/etc/hosts` dosyasını kontrol edin
2. Firewall ayarlarını kontrol edin: `sudo ufw status`
3. Sistem günlüklerini kontrol edin: `journalctl -xeu kubelet`
4. Container runtime durumunu kontrol edin: `systemctl status containerd`

## Notlar

- Bu scriptler, test ve geliştirme ortamları için tasarlanmıştır. Üretim ortamları için ek güvenlik yapılandırmaları gerekebilir.
- Kurulum yaklaşık 30-45 dakika sürebilir, özellikle SonarQube ve ArgoCD kurulumları zaman alabilir.
- Tüm şifre ve token bilgileri `/home/ubuntu/` dizininde saklanır. 