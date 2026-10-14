# Kubernetes-App

Eine Kubernetes-Lernumgebung für Hochschulkurse. Jedes Team bekommt einen
**eigenen Kubernetes-Cluster** (k3s, ein Node) auf einer eigenen VM. Jedes
Teammitglied meldet sich per SSH an und findet `kubectl` fertig eingerichtet
vor – mit einem eigenen Namespace und einem gemeinsamen Team-Namespace.

## Vorinstallierte Software

- k3s (stable channel) mit Traefik als Ingress-Controller und local-path-Storage
- kubectl (inkl. Tab-Vervollständigung, Alias `k`)
- helm
- k9s
- Git, curl, jq, vim, nano, htop

## Lernverzeichnis

Jeder Nutzer findet nach dem Login unter `~/k8s-kurs/` folgende Struktur:

    ~/k8s-kurs/
    ├── LIES_MICH.txt            ← Kurzreferenz und erste Schritte
    └── beispiele/
        ├── 01-pod.yaml          ← einzelner Pod
        ├── 02-deployment.yaml   ← Deployment mit 3 Replikas + Service
        ├── 03-nodeport.yaml     ← Service von außen erreichbar (Port 30080)
        └── 04-configmap.yaml    ← Konfiguration über ConfigMap

## User-Management

- **Ein Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `anna.schulz@dhbw.de` → Benutzername `annaschulz`)
- Jeder Nutzer erhält ein zufälliges Passwort, Login per SSH mit Passwort
- Kein `sudo`. Die Kubernetes-Rechte im Cluster:

| Namespace | Recht |
|---|---|
| `<benutzername>` | `admin` – eigener Namespace, Standard-Kontext |
| `team` | `admin` – gemeinsam für alle Teammitglieder |
| clusterweit | nur lesen: Nodes, Namespaces, StorageClasses, IngressClasses |

- Alle Nutzer-Namespaces erzwingen Pod Security **baseline**: privilegierte
  Pods, hostPath und Host-Netzwerk sind gesperrt. So kommt niemand über einen
  Pod an root auf dem Node.

## VM-Deployment

| | |
|---|---|
| VMs | **eine VM pro Team** – jedes Team hat einen eigenen Cluster |
| Flavor | im Wizard wählbar, Standard `gp1.small` |
| Betriebssystem | Ubuntu 24.04, Software wird beim ersten Boot per cloud-init installiert |
| Erreichbarkeit | IPv6-Adresse der VM, SSH auf Port 22 |
| Offene Ports | 22 (SSH), 80/443 (Traefik), 30000–32767 (NodePorts) |
| Bereit nach | ca. 5–6 Minuten nach dem Start der VM |
| Obergrenze | `max_teams`, Standard 15 Team-Cluster pro Deployment |

Ob die Ports 80/443 und die NodePorts tatsächlich von außen erreichbar sind,
hängt zusätzlich von der gewählten Security Group ab.

## Konfigurierbare Variablen

| Variable | Wizard-Feld | Standard |
|---|---|---|
| `image_name` | Image-Auswahl | `Ubuntu 24.04` |
| `network_uuid` | Netzwerk-Auswahl | DHBWV6-Netz |
| `shared_secgroup_id` | Security-Group-Auswahl | gemeinsame App-Store-SG |
| `flavor_name` | Flavor-Auswahl | `gp1.small` |
| `floating_ip_pool` | External-Network-Auswahl (derzeit ungenutzt) | `DHBW` |
| `max_teams` | Obergrenze | `15` |

`users` setzt der AppStore selbst.

## Aufbau

Reine OpenTofu-App nach ADR 0010: ein Ordner `tofu/`, kein Packer, kein
Image-Bau.

    Kubernetes-App/
    └── tofu/
        ├── main.tofu
        ├── variables.tofu
        ├── outputs.tofu
        ├── cloud-init.yml.tpl        ← legt Nutzer und Dateien an, startet die Skripte
        └── files/
            ├── install.sh            ← installiert k3s, kubectl, helm, k9s
            ├── k8s-provision.sh      ← startet den Cluster, richtet Nutzer-RBAC ein
            ├── profile.sh            ← Alias und Completion
            └── k8s-kurs/             ← Lernmaterial (→ /etc/skel)

Beim ersten Boot läuft zuerst `install.sh`, danach `k8s-provision.sh`. Die
Skripte gehen gzip-komprimiert in die `user_data` (etwa 12 KB, Limit 64 KB).

## Fehlersuche

Auf der VM (als Admin über die OpenStack-Konsole):

    cat /var/log/k8s-provision.log
    systemctl status k3s
    k3s kubectl get pods -A

## Lokale Checks

    cd tofu && tofu fmt -check && tofu init -backend=false && tofu validate
    shellcheck tofu/files/*.sh

## Release

Der AppStore deployt nur Git-Tags im Format `v<Major>.<Minor>.<Patch>`.

### v2.0.0

Umstellung auf OpenTofu (ADR 0010): Ordner `tofu/` mit `.tofu`-Dateien,
kein Packer mehr. Die Software wird beim ersten Boot installiert, der
Cluster ist daher erst nach etwa 5–6 Minuten bereit. Neue Wizard-Variable
`image_name` für das Basis-Image.

### v1.0.1

Eigenständiges kubectl für Nutzer, stabiler Erststart.

### v1.0.0

Erste Version: ein k3s-Cluster pro Team, eigener Namespace pro Nutzer,
gemeinsamer Team-Namespace, helm und k9s vorinstalliert.
