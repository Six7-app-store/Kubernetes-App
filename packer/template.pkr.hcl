packer {
  required_plugins {
    openstack = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/openstack"
    }
  }
}

locals {
  cloud                   = "openstack"
  flavor                  = "gp1.small"
  ssh_username            = "ubuntu"
  ssh_timeout             = "20m"
  use_blockstorage_volume = false
  volume_size             = 20
  use_floating_ip         = false
}

source "openstack" "image" {
  cloud                   = local.cloud
  image_name              = var.image_name
  source_image_name       = var.source_image_name
  flavor                  = local.flavor
  networks                = var.networks
  security_groups         = var.security_groups
  use_blockstorage_volume = local.use_blockstorage_volume
  volume_size             = local.volume_size
  use_floating_ip         = local.use_floating_ip
  ssh_ip_version          = "4"
  ssh_timeout             = local.ssh_timeout
  ssh_username            = local.ssh_username
}

build {
  sources = ["source.openstack.image"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init ready'",
      "mkdir -p /tmp/k8s-app"
    ]
  }

  # Dateien landen erst in /tmp, weil der Build-User nicht direkt nach
  # /usr/local oder /etc schreiben darf. provision.sh verschiebt sie.
  provisioner "file" {
    source      = "files/"
    destination = "/tmp/k8s-app"
  }

  provisioner "shell" {
    script          = "scripts/provision.sh"
    execute_command = "chmod +x {{ .Path }}; sudo -E bash '{{ .Path }}'"
    max_retries     = 3
  }
}
