#!/bin/bash
# approve-pending-csrs.sh - Approves pending CSRs for Talos Kubernetes nodes
# This script should be run after initial cluster creation to approve kubelet CSRs

# Exit on error
set -e

# Color codes for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Approving Pending Kubelet CSRs =====${NC}"

# Verify kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo -e "${YELLOW}kubectl not found. Please ensure it's installed and in your PATH.${NC}"
  exit 1
fi

# Check kubernetes connection
if ! kubectl get nodes &> /dev/null; then
  echo -e "${YELLOW}Cannot connect to Kubernetes. Please check your kubeconfig.${NC}"
  exit 1
fi

# Get all CSRs with 'Pending' in their condition
PENDING_CSRS=$(kubectl get csr | grep Pending | awk '{print $1}' || echo "")

if [ -z "$PENDING_CSRS" ]; then
  echo -e "${GREEN}No pending CSRs found! Your cluster may not need any approvals.${NC}"
  exit 0
fi

echo -e "Found $(echo "$PENDING_CSRS" | wc -l) pending CSRs. Approving..."

# Approve each CSR
for CSR in $PENDING_CSRS; do
  echo "Approving CSR: $CSR"
  kubectl certificate approve "$CSR"
done

echo -e "${GREEN}All pending CSRs have been approved!${NC}"
echo -e "${YELLOW}Note: The kubelet-serving-cert-approver should automatically approve future CSRs.${NC}"
echo "You can now proceed to the next step: installing Cilium CNI."
