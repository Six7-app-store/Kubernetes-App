#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Kubernetes-App: Erststart der Team-VM
#
# Aufgerufen von cloud-init (runcmd), nachdem die Linux-Nutzer angelegt sind.
# Startet den k3s-Cluster und richtet fuer jeden Nutzer ein:
#   - einen eigenen Namespace (Name = Benutzername) mit Rolle "admin"
#   - Rolle "admin" im gemeinsamen Namespace "team"
#   - Lesezugriff auf Nodes, Namespaces und StorageClasses
#   - ~/.kube/config mit einem Token fuer genau diese Rechte
#
# Die Nutzer bekommen KEIN sudo und keinen Zugriff auf die Admin-Kubeconfig
# (/etc/rancher/k3s/k3s.yaml, 0600 root). Pod Security "baseline" auf allen
# Nutzer-Namespaces verhindert privilegierte Pods und hostPath - sonst kaeme
# man ueber einen Pod doch an root auf dem Node.
#
# Idempotent: mehrfaches Ausfuehren legt nichts doppelt an.
# -----------------------------------------------------------------------------

USERS_FILE=/etc/k8s-app/users
TEAM_NS=team
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log() { echo "[$(date -Is)] $*"; }

# -----------------------------------------------------------------------------
# [1] k3s konfigurieren und starten
# -----------------------------------------------------------------------------
# Die oeffentliche IPv6-Adresse kommt ins API-Zertifikat, damit man den
# Cluster spaeter auch von aussen ansprechen koennte (Port 6443 ist in der
# Firewall aber bewusst zu - Zugriff laeuft ueber SSH).
ipv6=$(ip -6 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)

mkdir -p /etc/rancher/k3s
{
  echo 'write-kubeconfig-mode: "0600"'
  echo 'tls-san:'
  echo '  - "127.0.0.1"'
  if [ -n "$ipv6" ]; then echo "  - \"$ipv6\""; fi
} >/etc/rancher/k3s/config.yaml

log "Starting k3s..."
systemctl enable --now k3s

log "Waiting for the API server..."
for _ in $(seq 1 90); do
  kubectl get --raw /readyz >/dev/null 2>&1 && break
  sleep 5
done
kubectl wait --for=condition=Ready node --all --timeout=300s

# -----------------------------------------------------------------------------
# [2] Firewall
# -----------------------------------------------------------------------------
# Erst SSH freigeben, dann einschalten. Pod- und Service-Netz von k3s
# muessen durch, sonst erreichen Pods weder CoreDNS noch einander.
log "Configuring ufw..."
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 30000:32767/tcp
ufw allow from 10.42.0.0/16
ufw allow from 10.43.0.0/16
ufw --force enable

# -----------------------------------------------------------------------------
# [3] Gemeinsame RBAC-Objekte
# -----------------------------------------------------------------------------
apply_ns() {
  kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$1" --overwrite \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/warn=restricted
}

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-app-cluster-viewer
rules:
  - apiGroups: [""]
    resources: ["nodes", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingressclasses"]
    verbs: ["get", "list", "watch"]
EOF

apply_ns "$TEAM_NS"

server="https://127.0.0.1:6443"
ca_data=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# -----------------------------------------------------------------------------
# [4] Pro Nutzer: Namespace, ServiceAccount, Rechte, Kubeconfig
# -----------------------------------------------------------------------------
while read -r user; do
  [ -n "$user" ] || continue
  if ! id "$user" >/dev/null 2>&1; then
    log "WARN: Linux-Nutzer $user fehlt, uebersprungen"
    continue
  fi

  log "Setting up $user..."
  ns="$user"
  apply_ns "$ns"

  kubectl -n "$ns" create serviceaccount "$user" --dry-run=client -o yaml | kubectl apply -f -

  kubectl -n "$ns" create rolebinding "$user-admin" \
    --clusterrole=admin --serviceaccount="$ns:$user" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$TEAM_NS" create rolebinding "$user-admin" \
    --clusterrole=admin --serviceaccount="$ns:$user" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create clusterrolebinding "k8s-app-viewer-$user" \
    --clusterrole=k8s-app-cluster-viewer --serviceaccount="$ns:$user" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Langlebiges Token: seit Kubernetes 1.24 nur noch ueber ein explizites
  # Secret. Der Token-Controller fuellt es kurz nach dem Anlegen.
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $user-token
  namespace: $ns
  annotations:
    kubernetes.io/service-account.name: $user
type: kubernetes.io/service-account-token
EOF

  token=""
  for _ in $(seq 1 30); do
    token=$(kubectl -n "$ns" get secret "$user-token" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    [ -n "$token" ] && break
    sleep 2
  done
  if [ -z "$token" ]; then
    log "ERROR: kein Token fuer $user"
    continue
  fi

  home=$(getent passwd "$user" | cut -d: -f6)
  group=$(id -gn "$user")
  install -d -m 0700 -o "$user" -g "$group" "$home/.kube"
  umask 077
  cat >"$home/.kube/config" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: team-cluster
    cluster:
      server: $server
      certificate-authority-data: $ca_data
users:
  - name: $user
    user:
      token: $token
contexts:
  - name: $user
    context:
      cluster: team-cluster
      user: $user
      namespace: $ns
  - name: team
    context:
      cluster: team-cluster
      user: $user
      namespace: $TEAM_NS
current-context: $user
EOF
  chown "$user:$group" "$home/.kube/config"
  chmod 0600 "$home/.kube/config"
done <"$USERS_FILE"

log "Kubernetes-App bereit."
