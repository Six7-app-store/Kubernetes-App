#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Kubernetes-App: Software installieren (beim ersten Boot, als root)
# Installiert k3s (noch nicht gestartet), kubectl, helm und k9s. Den Cluster
# startet und konfiguriert danach k8s-provision.sh.
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update -y
apt-get install -y curl wget git vim nano htop jq bash-completion ufw ca-certificates

# -----------------------------------------------------------------------------
# [1] k3s installieren, aber nicht starten
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

apt-get clean
echo "Installation finished."
