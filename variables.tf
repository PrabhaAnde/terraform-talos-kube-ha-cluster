variable "proxmox_ssh_username" {
  description = "SSH username for Proxmox host (usually root)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_password" {
  description = "SSH password for Proxmox host (used for certain operations)"
  type        = string
  sensitive   = true
  # No default - should be provided securely in terraform.tfvars
}

variable "proxmox_api_url" {
  description = "The URL for the Proxmox API (https://your-proxmox-ip:8006/api2/json)"
  type        = string
  default     = "https://proxmox.local:8006/api2/json"
}

variable "proxmox_token_id" {
  description = "API Token ID for Proxmox (format: 'username@pam!tokenname')"
  type        = string
  # No default - should be provided in terraform.tfvars
}

variable "proxmox_token_secret" {
  description = "API Token Secret for Proxmox (generated when creating the token)"
  type        = string
  sensitive   = true
  # No default - should be provided securely in terraform.tfvars
}

variable "proxmox_node" {
  description = "Name of the Proxmox node (usually 'pve' for single-node setups)"
  type        = string
  default     = "pve"
}

variable "storage_pool" {
  description = "Proxmox storage pool to use for VM disks (e.g., ZFS pool name)"
  type        = string
  default     = "zpool1"
}

variable "cluster_name" {
  description = "Name for the Kubernetes cluster (used in Talos and kubeconfig)"
  type        = string
  default     = "talos-cluster"
}

variable "talos_version" {
  description = "Talos Linux version to install (check https://github.com/siderolabs/talos/releases for versions)"
  type        = string
  default     = "v1.9.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy (check compatibility with Talos version)"
  type        = string
  default     = "v1.29.3"
}

variable "control_plane_vip" {
  description = "Virtual IP address for the Kubernetes API server (high availability)"
  type        = string
  default     = "10.0.0.50"
}

variable "gateway" {
  description = "Network gateway IP address for all nodes"
  type        = string
  default     = "10.0.0.1"
}

variable "control_plane_nodes" {
  description = "List of control plane nodes with their Proxmox VM ID, name, and IP address"
  type = list(object({
    id   = number  # Proxmox VM ID (must be unique)
    name = string  # VM name
    ip   = string  # Static IP address
  }))
  default = [
    {
      id   = 810
      name = "tcp1"
      ip   = "10.0.0.60"
    },
    {
      id   = 811
      name = "tcp2"
      ip   = "10.0.0.61"
    },
    {
      id   = 812
      name = "tcp3"
      ip   = "10.0.0.62"
    }
  ]
}

variable "worker_nodes" {
  description = "List of worker nodes with their Proxmox VM ID, name, and IP address"
  type = list(object({
    id   = number  # Proxmox VM ID (must be unique)
    name = string  # VM name
    ip   = string  # Static IP address
  }))
  default = [
    {
      id   = 820
      name = "tworker1"
      ip   = "10.0.0.70"
    },
    {
      id   = 821
      name = "tworker2"
      ip   = "10.0.0.71"
    },
    {
      id   = 822
      name = "tworker3"
      ip   = "10.0.0.72"
    }
  ]
}