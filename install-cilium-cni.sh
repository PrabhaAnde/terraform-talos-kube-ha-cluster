#!/bin/bash
# install-cilium-cni.sh - Installs and configures Cilium CNI on a Talos Kubernetes cluster
# This script should be run after approving CSRs to replace the default CNI

# Exit on error
set -e

# Color codes for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default cluster information - should be adjusted for your environment
CLUSTER_NAME="talos-cluster"
CONTROL_PLANE_VIP="10.0.0.50"

echo -e "${GREEN}=== Talos Linux: Cilium CNI Setup Script ===${NC}"
echo -e "${YELLOW}This script will configure Talos, install Cilium CNI, and remove the default CNI${NC}"

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --control-plane-vip)
      CONTROL_PLANE_VIP="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--cluster-name NAME] [--control-plane-vip IP]"
      exit 1
      ;;
  esac
done

# Check for required tools
echo "Checking prerequisites..."
for cmd in kubectl talosctl curl; do
  if ! command_exists $cmd; then
    echo -e "${RED}Error: $cmd is not installed. Please install it before continuing.${NC}"
    exit 1
  fi
done

# Check if cluster is accessible
if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
  exit 1
fi

# Check if talosctl is properly configured
if ! talosctl version &>/dev/null; then
  echo -e "${RED}Error: talosctl is not properly configured. Please check your talosconfig.${NC}"
  exit 1
fi

# Step 1: Create CNI patch for Talos
echo "Creating CNI patch file for Talos..."
cat > cnipatch.yaml << EOF
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
EOF

echo -e "${GREEN}Created CNI patch file.${NC}"
echo "Content of cnipatch.yaml:"
cat cnipatch.yaml

# Step 2: Apply the patch to regenerate Talos configs
echo "Applying CNI patch to Talos cluster configuration..."
talosctl gen config $CLUSTER_NAME https://$CONTROL_PLANE_VIP:6443 --config-patch @cnipatch.yaml --force

echo -e "${YELLOW}The Talos configuration has been regenerated.${NC}"
echo -e "${YELLOW}You must now apply this new configuration to ALL your Talos nodes.${NC}"

# Ask for confirmation to continue
read -p "Have you applied the new configuration to all nodes? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${RED}Exiting. Please apply the configuration to all nodes before continuing.${NC}"
  echo "Use: talosctl apply-config --nodes <NODE-IP> --file <PATH-TO-CONFIG>"
  exit 1
fi

# Install Cilium CLI if not present
if ! command_exists cilium; then
  echo "Installing Cilium CLI..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    CLI_ARCH=arm64
  fi
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
  sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz
  echo -e "${GREEN}Cilium CLI installed successfully!${NC}"
else
  echo "Cilium CLI already installed, continuing..."
fi

# Install Cilium with Gateway API support
echo "Installing Cilium with Gateway API support..."
cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    # --set encryption.enabled=true \ # uncomment to enable encryption
    # --set encryption.type=wireguard \ # uncomment to use wireguard for encryption
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=$CONTROL_PLANE_VIP \
    --set k8sServicePort=6443 \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true

# Now that Cilium is installed, remove default CNI (like Flannel) if present
echo "Checking for Flannel resources..."
if kubectl get ds -n kube-system kube-flannel &>/dev/null; then
  echo "Removing Flannel DaemonSet..."
  kubectl delete ds -n kube-system kube-flannel
  
  # Remove other Flannel resources
  echo "Removing other Flannel resources..."
  for resource in clusterrolebinding/flannel clusterrole/flannel sa/flannel configmap/kube-flannel-cfg; do
    if kubectl get -n kube-system ${resource/*\//} &>/dev/null; then
      kubectl delete -n kube-system ${resource/*\//}
      echo "Deleted ${resource}"
    fi
  done
  echo -e "${GREEN}Default CNI resources removed.${NC}"
else
  echo "Default CNI DaemonSet not found, skipping removal."
fi

# Fix TLS errors with kubelet patch
echo "Creating kubelet patch file to fix TLS errors..."
cat > kubelet-patch.yaml << EOF
- op: add
  path: /machine/kubelet/extraArgs
  value:
    authorization-mode: "AlwaysAllow"
EOF

echo -e "${GREEN}Created kubelet patch file.${NC}"
echo "Content of kubelet-patch.yaml:"
cat kubelet-patch.yaml

# Get all node IPs
echo "Getting node IPs to apply kubelet patch..."
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

if [ -z "$NODE_IPS" ]; then
  echo -e "${RED}Error: Could not get node IPs from cluster. Please apply the patch manually.${NC}"
  echo "Use: talosctl -n <NODE-IP> patch mc -p @kubelet-patch.yaml"
else
  # Apply the patch to all nodes
  echo "Applying kubelet patch to all nodes..."
  for NODE_IP in $NODE_IPS; do
    echo "Patching node $NODE_IP..."
    if talosctl -n $NODE_IP patch mc -p @kubelet-patch.yaml; then
      echo -e "${GREEN}Successfully patched node $NODE_IP${NC}"
    else
      echo -e "${RED}Failed to patch node $NODE_IP${NC}"
    fi
  done
  
  echo -e "${YELLOW}Waiting 30 seconds for kubelet changes to take effect...${NC}"
  sleep 30
fi

# Verify installation
echo "Verifying Cilium status..."
cilium status --wait

echo "Verifying CoreDNS functionality with Cilium..."
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo -e "${GREEN}=== Cilium CNI setup complete! ===${NC}"
echo "You can verify Cilium status with: cilium status"
echo "To run connectivity tests: cilium connectivity test"
echo "You can now proceed to installing MetalLB for load balancing."
