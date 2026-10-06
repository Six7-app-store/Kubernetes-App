#cloud-config

# SSH mit Passwort-Auth aktivieren
ssh_pwauth: true

# Benutzer anlegen - ohne sudo. Kubernetes-Rechte vergibt k8s-provision.sh.
# jsonencode() quotet jeden Wert, damit YAML nichts davon umdeutet.
users:
%{ for user in team_users ~}
  - name: ${jsonencode(user.username)}
    shell: /bin/bash
    lock_passwd: false
%{ endfor ~}

# Passwoerter zwingend ueber jsonencode(): eines, das mit ! @ % oder *
# beginnt, waere als unquotierter Skalar ein YAML-Syntaxfehler.
chpasswd:
  expire: false
  users:
%{ for user in team_users ~}
    - name: ${jsonencode(user.username)}
      password: ${jsonencode(user.password)}
      type: text
%{ endfor ~}

write_files:
  - path: /etc/ssh/sshd_config.d/99-k8s-app.conf
    permissions: '0644'
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
      UsePAM yes

  # Liste der Nutzer, eine Zeile pro Benutzername; liest k8s-provision.sh.
  - path: /etc/k8s-app/users
    permissions: '0600'
    owner: 'root:root'
    content: |
%{ for user in team_users ~}
      ${user.username}
%{ endfor ~}

  - path: /etc/k8s-app/team
    permissions: '0644'
    content: ${jsonencode(team_name)}

  # Skripte und Lernmaterial (aus tofu/files/, gzip+base64).
  - path: /usr/local/sbin/k8s-install.sh
    permissions: '0755'
    encoding: gz+b64
    content: ${install_gz}

  - path: /usr/local/bin/k8s-provision.sh
    permissions: '0755'
    encoding: gz+b64
    content: ${provision_gz}

  - path: /etc/profile.d/k8s-app.sh
    permissions: '0644'
    encoding: gz+b64
    content: ${profile_gz}

%{ for name, data in kurs_files ~}
  - path: ${jsonencode("/etc/skel/k8s-kurs/${name}")}
    permissions: '0644'
    encoding: gz+b64
    content: ${data}

%{ endfor ~}
# Erst Software installieren, dann Cluster und Nutzer einrichten.
runcmd:
  - systemctl restart ssh
  - bash -c "/usr/local/sbin/k8s-install.sh && /usr/local/bin/k8s-provision.sh" > /var/log/k8s-provision.log 2>&1

final_message: "Kubernetes-Team-Cluster bereit - Log unter /var/log/k8s-provision.log"
