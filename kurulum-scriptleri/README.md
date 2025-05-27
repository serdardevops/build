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

### API Sunucusu Başlatma Hatası

Eğer "The API server is not healthy" veya "context deadline exceeded" hatası alırsanız:

1. Öncelikle kubelet servisinin durumunu kontrol edin:
   ```bash
   systemctl status kubelet
   journalctl -xeu kubelet
   ```

2. API sunucusu konteynerlerini kontrol edin:
   ```bash
   crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube-apiserver
   ```

3. API sunucusu günlüklerini inceleyin:
   ```bash
   CONTAINER_ID=$(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube-apiserver | awk '{print $1}')
   crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock logs $CONTAINER_ID
   ```

4. Bellek ve CPU kaynaklarının yeterli olduğundan emin olun:
   ```bash
   free -m
   top
   ```

5. Önceki kurulumu temizleyin ve tekrar deneyin:
   ```bash
   kubeadm reset -f
   systemctl restart containerd kubelet
   kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.1.137 --v=5
   ```

6. Swap'ın kapalı olduğundan emin olun:
   ```bash
   swapoff -a
   free -m | grep Swap
   ```

7. Port 6443'ün kullanılabilir olduğundan emin olun:
   ```bash
   netstat -tulpn | grep 6443
   ```

#### Yaygın Hata Nedenleri ve Çözümleri

1. **"certificate signed by unknown authority" Hatası**:
   - Sorun: API sunucusu sertifika hatası veriyor
   - Çözüm:
     ```bash
     kubeadm reset -f
     rm -rf /etc/kubernetes/pki
     rm -rf $HOME/.kube
     kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.1.137
     ```

2. **"Port 6443 already in use" Hatası**:
   - Sorun: 6443 portu başka bir servis tarafından kullanılıyor
   - Çözüm:
     ```bash
     lsof -i:6443
     # Portu kullanan uygulamayı durdurun
     kill -9 PID_NUMARASI
     # Veya
     systemctl stop SERVIS_ADI
     ```

3. **"Failed to pull image" Hatası**:
   - Sorun: Docker imajları çekilemiyor
   - Çözüm:
     ```bash
     # DNS ayarlarını kontrol edin
     cat /etc/resolv.conf
     # Geçici çözüm olarak Google DNS ekleyin
     echo "nameserver 8.8.8.8" > /etc/resolv.conf
     # Containerd servisini yeniden başlatın
     systemctl restart containerd
     ```

4. **"kubelet isn't running or healthy" Hatası**:
   - Sorun: kubelet servisi düzgün çalışmıyor
   - Çözüm:
     ```bash
     # cgroup sürücüsünü kontrol edin
     cat /etc/containerd/config.toml | grep SystemdCgroup
     # config.toml'u düzenleyin ve SystemdCgroup = true olarak ayarlayın
     sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
     # Servisleri yeniden başlatın
     systemctl restart containerd kubelet
     ```

5. **"misconfiguration: kubeletInsufficientMemory" Hatası**:
   - Sorun: Makinede yeterli bellek yok
   - Çözüm:
     ```bash
     # Swap'ı kapatın ve gereksiz servisleri durdurun
     swapoff -a
     # Bellek tüketimini kontrol edin
     free -m
     # Fazla bellek kullanan uygulamaları durdurun
     systemctl stop jenkins sonarqube
     ```

6. **"network plugin is not ready" Hatası**:
   - Sorun: CNI eklentisi düzgün yapılandırılmamış
   - Çözüm:
     ```bash
     # Flannel kurulumunu tekrar yapın
     kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
     # Kernel modüllerinin yüklendiğinden emin olun
     modprobe br_netfilter
     modprobe overlay
     ```

7. **"error during CRI logging parsing" Hatası**:
   - Sorun: containerd log yapılandırması sorunlu
   - Çözüm:
     ```bash
     # containerd yapılandırmasını sıfırlayın
     systemctl stop containerd
     rm -rf /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db
     systemctl start containerd
     ```

#### API Sunucusu Tam Yeniden Başlatma

Tüm çözümler başarısız olursa, komple temizlik ve yeniden kurulum deneyin:

```bash
# Kubernetes'i tamamen sıfırlayın
kubeadm reset -f
systemctl stop kubelet containerd
systemctl disable kubelet containerd

# Dosya sistemini temizleyin
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /var/lib/containerd
rm -rf /var/run/kubernetes
rm -rf $HOME/.kube

# Servisleri yeniden başlatın
systemctl enable containerd kubelet
systemctl start containerd kubelet

# Yeniden kurun
kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.1.137 --v=5
```

## Notlar

- Bu scriptler, test ve geliştirme ortamları için tasarlanmıştır. Üretim ortamları için ek güvenlik yapılandırmaları gerekebilir.
- Kurulum yaklaşık 30-45 dakika sürebilir, özellikle SonarQube ve ArgoCD kurulumları zaman alabilir.
- Tüm şifre ve token bilgileri `/home/ubuntu/` dizininde saklanır. 