#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Kubernetes-App: Image-Provisioning
#
# Ins Image kommt nur, was fuer alle Teams gleich ist: k3s (installiert, aber
# NICHT gestartet), kubectl, helm, k9s und das Lernmaterial in /etc/skel.
#
# Der Cluster selbst wird erst beim ersten Start der Team-VM initialisiert
# (k8s-provision.sh). Wuerde k3s schon hier laufen, steckten im Image die
# Zertifikate, der Node-Name und die IP-Adresse der Build-VM - jede daraus
# gestartete VM haette dann einen Cluster mit falscher Identitaet.
#
# Laeuft als root (execute_command in template.pkr.hcl).
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
    sh -

# Der Installer legt kubectl als Symlink auf k3s an; pruefen, dass er da ist.
k3s --version
kubectl version --client

# -----------------------------------------------------------------------------
# [2] helm und k9s
# -----------------------------------------------------------------------------
echo "Installing helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo "Installing k9s..."
arch=$(dpkg --print-architecture)
curl -fsSL -o /tmp/k9s.deb "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${arch}.deb"
apt-get install -y /tmp/k9s.deb
rm -f /tmp/k9s.deb

# -----------------------------------------------------------------------------
# [3] Erststart-Skript und Lernmaterial
# -----------------------------------------------------------------------------
install -m 0755 /tmp/k8s-app/k8s-provision.sh /usr/local/bin/k8s-provision.sh
install -m 0644 /tmp/k8s-app/profile.sh /etc/profile.d/k8s-app.sh

# Alles unter /etc/skel bekommt jeder Nutzer, den cloud-init anlegt.
mkdir -p /etc/skel/k8s-kurs
cp -r /tmp/k8s-app/k8s-kurs/. /etc/skel/k8s-kurs/
rm -rf /tmp/k8s-app

# -----------------------------------------------------------------------------
# [4] Cleanup
# -----------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Provisioning finished."
