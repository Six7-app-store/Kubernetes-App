#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Kubernetes-App: Image-Provisioning (laeuft als root)
# k3s wird nur installiert, gestartet wird es erst auf der Team-VM
# (k8s-provision.sh) - sonst haette jede VM die Identitaet der Build-VM.
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update -y
apt-get install -y curl wget git vim nano htop jq bash-completion ufw ca-certificates

# -----------------------------------------------------------------------------
# [1] k3s installieren, aber nicht aktivieren
# -----------------------------------------------------------------------------
echo "Installing k3s (stable channel, service disabled)..."
curl -sfL https://get.k3s.io |
  INSTALL_K3S_CHANNEL=stable \
    INSTALL_K3S_SKIP_ENABLE=true \
    INSTALL_K3S_SKIP_START=true \
    INSTALL_K3S_SYMLINK=skip \
    sh -
k3s --version

# Echtes kubectl: das von k3s ignoriert ~/.kube/config.
k8s_version=$(k3s --version | awk 'NR==1 {print $3}' | cut -d+ -f1)
arch=$(dpkg --print-architecture)
echo "Installing kubectl ${k8s_version}..."
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${k8s_version}/bin/linux/${arch}/kubectl"
chmod 0755 /usr/local/bin/kubectl
kubectl version --client

# -----------------------------------------------------------------------------
# [2] helm und k9s
# -----------------------------------------------------------------------------
echo "Installing helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo "Installing k9s..."
curl -fsSL -o /tmp/k9s.deb "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${arch}.deb"
apt-get install -y /tmp/k9s.deb
rm -f /tmp/k9s.deb

# -----------------------------------------------------------------------------
# [3] Erststart-Skript und Lernmaterial
# -----------------------------------------------------------------------------
install -m 0755 /tmp/k8s-app/k8s-provision.sh /usr/local/bin/k8s-provision.sh
install -m 0644 /tmp/k8s-app/profile.sh /etc/profile.d/k8s-app.sh

# /etc/skel landet im Home jedes neuen Nutzers.
mkdir -p /etc/skel/k8s-kurs
cp -r /tmp/k8s-app/k8s-kurs/. /etc/skel/k8s-kurs/
rm -rf /tmp/k8s-app

# -----------------------------------------------------------------------------
# [4] Cleanup
# -----------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Provisioning finished."
