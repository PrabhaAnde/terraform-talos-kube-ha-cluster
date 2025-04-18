# Terraform configuration for Talos Kubernetes cluster with Cilium CNI
# This creates a high-availability Kubernetes cluster on Proxmox using Talos Linux

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.75.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.1"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure = true  # Set to false in production with proper certificates
  
  ssh {
    agent    = false
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}

resource "proxmox_virtual_environment_file" "talos_disk" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_file {
    path = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.9.5/nocloud-amd64.iso"
  }
}

resource "proxmox_virtual_environment_vm" "control_plane_nodes" {
  count       = length(var.control_plane_nodes)
  name        = var.control_plane_nodes[count.index].name
  description = "Talos Kubernetes control plane node"
  node_name   = var.proxmox_node
  vm_id       = var.control_plane_nodes[count.index].id

  cpu {
    cores = 2
    type  = "host"
  }
  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = proxmox_virtual_environment_file.talos_disk.id
    interface    = "scsi0"
    ssd          = true
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.storage_pool
    ip_config {
      ipv4 {
        address = "${var.control_plane_nodes[count.index].ip}/24"
        gateway = var.gateway
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker_nodes" {
  count       = length(var.worker_nodes)
  name        = var.worker_nodes[count.index].name
  description = "Talos Kubernetes worker node"
  node_name   = var.proxmox_node
  vm_id       = var.worker_nodes[count.index].id

  cpu {
    cores = 4
    type  = "host"
  }
  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = proxmox_virtual_environment_file.talos_disk.id
    interface    = "scsi0"
    size         = 40
    ssd          = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.storage_pool
    ip_config {
      ipv4 {
        address = "${var.worker_nodes[count.index].ip}/24"
        gateway = var.gateway
      }
    }
  }
}

resource "talos_machine_secrets" "this" {}

locals {
  controlplane_patch = <<-EOT
machine:
  network:
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  time:
    servers:
      - time.cloudflare.com
  install:
    disk: /dev/sda
    image: ghcr.io/siderolabs/installer:v1.9.5
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry-1.docker.io
      gcr.io:
        endpoints:
          - https://gcr.io
      ghcr.io:
        endpoints:
          - https://ghcr.io
      k8s.gcr.io:
        endpoints:
          - https://registry.k8s.io
      quay.io:
        endpoints:
          - https://quay.io
  kubelet:
    extraArgs:
      rotate-server-certificates: true

cluster:
  network:
    cni:
      name: none
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true
  etcd:
    advertisedSubnets:
      - 10.0.0.0/24
EOT

  worker_patch = <<-EOT
machine:
  network:
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  time:
    servers:
      - time.cloudflare.com
  install:
    disk: /dev/sda
    image: ghcr.io/siderolabs/installer:v1.9.5
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry-1.docker.io
      gcr.io:
        endpoints:
          - https://gcr.io
      ghcr.io:
        endpoints:
          - https://ghcr.io
      k8s.gcr.io:
        endpoints:
          - https://registry.k8s.io
      quay.io:
        endpoints:
          - https://quay.io
  kubelet:
    extraArgs:
      rotate-server-certificates: true
EOT
}

data "talos_machine_configuration" "control_plane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "controlplane"
  kubernetes_version = var.kubernetes_version
  talos_version    = var.talos_version
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  
  config_patches = [
    local.controlplane_patch,    
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  kubernetes_version = var.kubernetes_version
  talos_version    = var.talos_version
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  
  config_patches = [
    local.worker_patch,
    
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        },
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for node in var.control_plane_nodes : node.ip]
  nodes                = [for node in var.control_plane_nodes : node.ip]
}

resource "talos_machine_configuration_apply" "control_plane" {
  depends_on = [
    proxmox_virtual_environment_vm.control_plane_nodes
  ]
  count                = length(var.control_plane_nodes)
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                 = var.control_plane_nodes[count.index].ip
  
  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${var.control_plane_nodes[count.index].ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              vip = { ip = var.control_plane_vip }
            }
          ]
          extraHostEntries = [
            {
              ip = var.control_plane_vip
              aliases = ["api.talos-cluster.local"]
            }
          ]
          kubespan = {
            enabled = false
          }
        }
        kubelet = {
          extraArgs = {
            "node-ip" = var.control_plane_nodes[count.index].ip
          }
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  depends_on = [
    proxmox_virtual_environment_vm.worker_nodes
  ]
  count                = length(var.worker_nodes)
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                 = var.worker_nodes[count.index].ip
  
  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${var.worker_nodes[count.index].ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
          kubespan = {
            enabled = false
          }
        }
        kubelet = {
          extraArgs = {
            "node-ip" = var.worker_nodes[count.index].ip
          }
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.control_plane
  ]
  
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes[0].ip
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]
  
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes[0].ip
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/kubeconfig"
}