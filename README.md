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
| Betriebssystem | Ubuntu 24.04 (Packer-Image) |
| Erreichbarkeit | IPv6-Adresse der VM, SSH auf Port 22 |
| Offene Ports | 22 (SSH), 80/443 (Traefik), 30000–32767 (NodePorts) |
| Bereit nach | ca. 3 Minuten nach dem Start der VM |
| Obergrenze | `max_teams`, Standard 15 Team-Cluster pro Deployment |

Ob die Ports 80/443 und die NodePorts tatsächlich von außen erreichbar sind,
hängt zusätzlich von der gewählten Security Group ab.

## Konfigurierbare Variablen

| Variable | Wizard-Feld | Standard |
|---|---|---|
| `network_uuid` | Netzwerk-Auswahl | DHBWV6-Netz |
| `shared_secgroup_id` | Security-Group-Auswahl | gemeinsame App-Store-SG |
| `flavor_name` | Flavor-Auswahl | `gp1.small` |
| `floating_ip_pool` | External-Network-Auswahl (derzeit ungenutzt) | `DHBW` |
| `max_teams` | Obergrenze | `15` |

`users` und `image_name` setzt der AppStore selbst (`@platform:internal`).

## Aufbau

    Kubernetes-App/
    ├── packer/
    │   ├── template.pkr.hcl
    │   ├── variables.pkr.hcl
    │   ├── scripts/provision.sh      ← baut das Image (k3s, helm, k9s)
    │   └── files/
    │       ├── k8s-provision.sh      ← Erststart: Cluster + Nutzer-RBAC
    │       ├── profile.sh            ← Alias und Completion
    │       └── k8s-kurs/             ← Lernmaterial (→ /etc/skel)
    └── terraform/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── cloud-init.yml.tpl

**Warum startet k3s erst auf der Team-VM?** Würde der Cluster schon beim
Image-Bau laufen, steckten Zertifikate, Node-Name und IP der Build-VM im Image.
Packer installiert k3s deshalb nur; `k8s-provision.sh` startet ihn beim
ersten Boot und richtet danach Namespaces, ServiceAccounts und die
`~/.kube/config` jedes Nutzers ein.

## Fehlersuche

Auf der VM (als Admin über die OpenStack-Konsole):

    cat /var/log/k8s-provision.log
    systemctl status k3s
    k3s kubectl get pods -A

## Lokale Checks

    cd terraform && tofu fmt -check && tofu init -backend=false && tofu validate
    cd packer && packer fmt -check . && packer init . && packer validate -syntax-only .

## Release

Der AppStore deployt nur Git-Tags im Format `v<Major>.<Minor>.<Patch>`.

### v1.0.0

Erste Version: ein k3s-Cluster pro Team, eigener Namespace pro Nutzer,
gemeinsamer Team-Namespace, helm und k9s vorinstalliert.
