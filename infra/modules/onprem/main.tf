terraform {
  required_version = ">= 1.11"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

provider "docker" {
  host = var.docker_host

  ssh_opts = [
    "-i", var.ssh_key_path,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=${var.known_hosts_path}"
  ]
}

resource "docker_image" "app" {
  name         = "${var.image}:${var.image_tag}"
  platform     = "linux/amd64"
  keep_locally = true
}

resource "docker_container" "app" {
  name    = "daisy-hellocalc-onprem"
  image   = docker_image.app.image_id
  restart = "unless-stopped"

  ports {
    internal = var.port
    external = var.host_port
    ip       = var.host_ip
  }
}
