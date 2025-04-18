proxmox_api_url = "https://your-proxmox-ip:8006/api2/json"
proxmox_token_id = "your-username@pam!token-name"
proxmox_token_secret = "your-token-secret-here"

# proxmox_ssh_username = "root"
# proxmox_ssh_password = "your-ssh-password"

# Storage configuration
storage_pool = "local-lvm"    # Replace with your ZFS or local / local-lvm  name

# Cluster configuration
cluster_name = "talos-kube-cluster"
talos_version = "v1.9.5"
kubernetes_version = "v1.29.3"
control_plane_vip = "10.0.0.50"   # Virtual IP for the control plane
gateway = "10.0.0.1"              # Your network gateway

# Node configurations
# Customize IPs to match your network environment
control_plane_nodes = [
  {
    id   = 810                    # VM ID in Proxmox
    name = "tcp1"                 # VM name
    ip   = "10.0.0.60"            # Static IP for this node
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

worker_nodes = [
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