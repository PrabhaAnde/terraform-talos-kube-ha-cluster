# Talos Kubernetes HA Cluster Automation with Terraform on Proxmox

This project provides infrastructure-as-code to deploy a production grade high-availability Kubernetes cluster using [Talos Linux](https://www.talos.dev/) on Proxmox virtualization. It uses Terraform for provisioning and includes post-installation scripts for Kubernetes configuration and CNI setup.

## Overview

This project creates:
- A multi-node Talos Linux Kubernetes cluster
- High availability control plane with virtual IP (VIP)
- Worker nodes for application workloads
- Cilium as the Container Network Interface (CNI)
- Optional MetalLB load balancer

## Prerequisites

Before you begin, ensure you have:

- **Proxmox VE** server installed and configured (tested with 7.4+)
- **Terraform** installed on your local machine ([Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli))
- **Required Terraform providers**:
  - Proxmox Provider ([bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs))
  - Talos Provider ([siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos/latest/docs))
- **kubectl** installed on your local machine ([Installation Guide](https://kubernetes.io/docs/tasks/tools/install-kubectl/))
- **talosctl** installed on your local machine ([Installation Guide](https://www.talos.dev/v1.9/introduction/getting-started/#talosctl))
- **Network planning**:
  - A dedicated subnet for your Kubernetes cluster
  - Static IP addresses for control plane and worker nodes
  - A virtual IP address for the Kubernetes API server (control plane VIP)

## Network Architecture

This deployment creates the following network structure:

- **Control Plane Nodes**: 3 VMs configured as Talos control plane nodes
- **Worker Nodes**: 3 VMs configured as Talos worker nodes
- **Control Plane VIP**: A virtual IP for HA Kubernetes API endpoint
- **Pod Network**: 10.244.0.0/16 (configurable)
- **Service Network**: 10.96.0.0/12 (configurable)

## Getting Started

### Step 1: Configure Terraform Variables

1. Edit `terraform.tfvars` file with your Proxmox and network details:

```hcl
proxmox_api_url = "https://your-proxmox-ip:8006/api2/json"
proxmox_token_id = "your-username@pam!token-name"
proxmox_token_secret = "your-token-secret-here"

# Storage configuration
storage_pool = "local-lvm"    # Replace with your storage pool name

# Cluster configuration 
cluster_name = "talos-kube-cluster"
talos_version = "v1.9.5"
kubernetes_version = "v1.29.3"
control_plane_vip = "10.0.0.50"   # Virtual IP for the control plane
gateway = "10.0.0.1"              # Your network gateway

# Customize IP addresses to match your network
control_plane_nodes = [
  { id = 810, name = "tcp1", ip = "10.0.0.60" },
  { id = 811, name = "tcp2", ip = "10.0.0.61" },
  { id = 812, name = "tcp3", ip = "10.0.0.62" }
]

worker_nodes = [
  { id = 820, name = "tworker1", ip = "10.0.0.70" },
  { id = 821, name = "tworker2", ip = "10.0.0.71" },
  { id = 822, name = "tworker3", ip = "10.0.0.72" }
]
```

### Step 2: Initialize Terraform

```bash
terraform init
```

This will download the required Terraform providers.

### Step 3: Plan and Apply Terraform Configuration

```bash
terraform plan
terraform apply
```

This process:
1. Prompts for SSH login credentials to connect to your Proxmox host
2. Downloads the Talos Linux ISO to Proxmox
3. Creates control plane and worker VMs
4. Configures Talos on all nodes
5. Bootstraps the Kubernetes cluster
6. Generates `talosconfig` and `kubeconfig` files in your current directory
### Step 4: Configure Local Access

The Terraform process generates two configuration files:

- `talosconfig` - For accessing Talos API endpoints
- `kubeconfig` - For accessing Kubernetes API

Set them as environment variables:

```bash
export TALOSCONFIG=$(pwd)/talosconfig
export KUBECONFIG=$(pwd)/kubeconfig
```

### Step 5: Approve Pending CSRs

Run the included script to approve any pending Certificate Signing Requests (CSRs):

```bash
chmod +x approve-pending-csrs.sh
./approve-pending-csrs.sh
```

This step ensures all Kubernetes nodes can join the cluster properly.

### Step 6: Install Cilium CNI (Required)

The Terraform configuration explicitly disables the default CNI (Flannel) that comes with Talos. You must install a CNI, and this project includes a script to install Cilium:

```bash
chmod +x install-cilium-cni.sh
./install-cilium-cni.sh --cluster-name talos-kube-cluster --control-plane-vip 10.0.0.50
```

This script will:
1. Verify prerequisites
2. Create and apply a CNI patch
3. Install Cilium with Gateway API support
4. Remove any remnants of the default CNI
5. Apply a kubelet patch to fix potential TLS errors

Wait for Cilium to be fully operational before proceeding.

#### Encrypting Network Traffic with Wireguard

By default, network encryption is disabled. To enable Wireguard encryption for Cilium, refer to lines 118-119 in the installation script. Uncomment and modify the Helm values to activate Wireguard encryption. For detailed information about Cilium's Wireguard encryption implementation, see the [official documentation](https://docs.cilium.io/en/latest/security/network/encryption-wireguard/#encryption-wg).
### Step 7: Verify Cluster Status

Check if all nodes are ready:

```bash
kubectl get nodes
```

Check if all system pods are running:

```bash
kubectl get pods -n kube-system
```

### Step 8: (Optional) Install MetalLB for Load Balancer Services

If you need LoadBalancer service support, install MetalLB:

```bash
chmod +x install-metallb-loadbalancer.sh
./install-metallb-loadbalancer.sh --ip-range 10.0.0.30-10.0.0.59
```

Adjust the IP range to match your network environment.

## Talos Management

Talos Linux provides a unique management approach compared to traditional Linux distributions. Here are some common operations:

### Checking Node Status

```bash
talosctl --nodes 10.0.0.60 dashboard
```

### Updating Talos Configuration

```bash
talosctl --nodes 10.0.0.60 apply-config -f /path/to/config.yaml
```

### Rebooting a Node

```bash
talosctl --nodes 10.0.0.60 reboot
```

### Accessing Logs

```bash
talosctl --nodes 10.0.0.60 logs
```

## Troubleshooting

### Common Issues

1. **CSR Approval Problems**: If nodes are not joining the cluster, ensure all CSRs are approved:
   ```bash
   kubectl get csr
   kubectl certificate approve <csr-name>
   ```

2. **Networking Issues**: If pods can't communicate, verify Cilium is running correctly:
   ```bash
   kubectl -n kube-system get pods -l k8s-app=cilium
   cilium status --wait
   ```

3. **API Server Unreachable**: Check if the control plane VIP is working:
   ```bash
   ping 10.0.0.50
   ```

4. **Node Status NotReady**: Check kubelet status:
   ```bash
   talosctl --nodes <node-ip> service kubelet status
   ```

### Getting Help

For more advanced troubleshooting:

1. Check the [Talos Documentation](https://www.talos.dev/v1.9/talos-guides/install/)
2. Check the [Cilium Documentation](https://docs.cilium.io/en/stable/)

## Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Proxmox Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Cilium Documentation](https://docs.cilium.io/en/stable/)
- [MetalLB Documentation](https://metallb.universe.tf/)

## Upgrading

Please refer to the [Talos Linux Upgrade Guide](https://www.talos.dev/v1.9/talos-guides/upgrading-talos/) for instructions on upgrading your Talos nodes.

## License

This project is provided as-is under an open-source license.