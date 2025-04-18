#!/bin/bash
# install-metallb-loadbalancer.sh - Installs and configures MetalLB for load balancing
# This script provides external LoadBalancer services for your Kubernetes cluster
set -e

# Color codes for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default IP range - you should modify this to match your specific network
DEFAULT_IP_RANGE="10.0.0.30-10.0.0.59"

echo -e "${GREEN}=== Talos Kubernetes: MetalLB Setup Script ===${NC}"
echo -e "${YELLOW}This script will install and configure MetalLB load balancer${NC}"

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Parse command-line arguments
IP_RANGE=$DEFAULT_IP_RANGE
while [[ $# -gt 0 ]]; do
  case $1 in
    --ip-range)
      IP_RANGE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--ip-range IP_RANGE]"
      echo "  --ip-range     Specify IP address range for MetalLB (default: $DEFAULT_IP_RANGE)"
      echo "Example: $0 --ip-range 192.168.1.200-192.168.1.250"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--ip-range 10.0.0.200-10.0.0.250]"
      echo "Try '$0 --help' for more information"
      exit 1
      ;;
  esac
done

# Check for required tools
echo "Checking prerequisites..."
for cmd in kubectl helm; do
  if ! command_exists $cmd; then
    echo -e "${RED}Error: $cmd is not installed. Please install it before continuing.${NC}"
    if [ "$cmd" = "helm" ]; then
      echo "To install helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    fi
    exit 1
  fi
done

# Check if Kubernetes cluster is accessible
if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
  exit 1
fi

# Create metallb-system namespace with proper security context
echo "Creating metallb-system namespace with proper security context..."
if ! kubectl get namespace metallb-system &>/dev/null; then
  kubectl create namespace metallb-system
else
  echo "Namespace metallb-system already exists, continuing..."
fi

# Apply security labels to namespace for pod security
echo "Setting Pod Security policies on namespace..."
kubectl label namespace metallb-system pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace metallb-system pod-security.kubernetes.io/audit=privileged --overwrite
kubectl label namespace metallb-system pod-security.kubernetes.io/warn=privileged --overwrite

# Add Helm repository for MetalLB
echo "Adding MetalLB Helm repository..."
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Install MetalLB controller and components using Helm
echo "Installing MetalLB via Helm..."
if ! kubectl get deployment -n metallb-system metallb-controller &>/dev/null; then
  helm install metallb metallb/metallb --namespace metallb-system
  echo -e "${GREEN}MetalLB installed successfully.${NC}"
else
  echo "MetalLB controller already exists, skipping installation."
  echo "To upgrade: helm upgrade metallb metallb/metallb --namespace metallb-system"
fi

# Wait for MetalLB pods to be ready before continuing
echo "Waiting for MetalLB pods to be ready..."
if ! kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=metallb \
  --timeout=200s; then
    echo -e "${YELLOW}Warning: MetalLB pods did not become ready within timeout.${NC}"
    echo "Checking MetalLB pod status:"
    kubectl get pods -n metallb-system
    echo "Continuing despite timeout, but you may need to investigate..."
fi

# Create IPAddressPool Custom Resource for MetalLB
echo "Creating IPAddressPool with IP range: $IP_RANGE"
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - $IP_RANGE
EOF

# Create L2Advertisement Custom Resource to advertise the IP pool
echo "Creating L2Advertisement..."
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF

echo -e "${GREEN}=== MetalLB setup complete! ===${NC}"
echo "Configuration summary:"
echo "- IP range for LoadBalancers: $IP_RANGE"
echo "- L2 advertisement mode enabled (ARP-based)"
echo ""
echo "To verify installation, check the resources:"
echo "  kubectl get all -n metallb-system"
echo ""
echo "To test with a sample deployment:"
echo "  kubectl create deployment nginx-test --image=nginx --port=80"
echo "  kubectl expose deployment nginx-test --type=LoadBalancer --port=80"
echo "  kubectl get service nginx-test"
echo ""
echo "You should see an external IP assigned from the range: $IP_RANGE"
