#!/usr/bin/env bash
# Talos Linux Cluster Bootstrap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# =============================================================================
# Usage & Argument Parsing
# =============================================================================

usage() {
  echo "Usage: $0 [-n node:ip ...] <cluster_name>"
  echo ""
  echo "Options:"
  echo "  -n node:ip    Specify node (can be used multiple times)"
  echo "  -h            Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 delluster"
  echo "  $0 -n nodes/node1.yaml:192.168.178.181 delluster"
  echo "  $0 -n node1.yaml:192.168.1.10 -n node2.yaml:192.168.1.11 delluster"
  exit 1
}

NODES=()

# Parse options with getopts
while getopts "n:h" opt; do
  case "$opt" in
    n) NODES+=("$OPTARG");;
    h) usage;;
    \?) usage;;
  esac
done

# Shift past the processed options
shift $((OPTIND-1))

# Get cluster name (first remaining argument)
if [ $# -eq 0 ]; then
  echo "Error: cluster_name is required"
  usage
fi

CLUSTER_NAME="$1"

# =============================================================================
# Auto-Discovery
# =============================================================================

# Read VIP from vip.yaml
echo "Reading VIP from patches/vip.yaml..."
VIP=$(yq -e '.machine.network.interfaces[0].vip.ip' patches/vip.yaml)

if [ -z "$VIP" ]; then
  echo "Error: Could not read VIP from patches/vip.yaml"
  exit 1
fi
echo "✓ VIP: ${VIP}"

# Auto-discover nodes if none specified via -n flag
if [ ${#NODES[@]} -eq 0 ]; then
  echo "Auto-discovering nodes from nodes/ directory..."
  for node_file in nodes/*.yaml; do
    [ -f "$node_file" ] || continue

    NODE_IP=$(yq -e '.machine.network.interfaces[0].addresses[0]' "$node_file" | cut -d'/' -f1)

    if [ -n "$NODE_IP" ]; then
      NODES+=("${node_file}:${NODE_IP}")
      echo "  → ${node_file} (${NODE_IP})"
    else
      echo "  ⚠ Skipping ${node_file} (no IP found)"
    fi
  done
else
  echo "Using specified nodes..."
  for node in "${NODES[@]}"; do
    echo "  → ${node}"
  done
fi

if [ ${#NODES[@]} -eq 0 ]; then
  echo "Error: No nodes found"
  exit 1
fi

# Extract IP addresses for health checks
NODE_IPS=()
for node_entry in "${NODES[@]}"; do
  NODE_IPS+=("${node_entry##*:}")
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Talos Bootstrap: ${CLUSTER_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  VIP:     ${VIP}"
echo "  Nodes:   ${#NODES[@]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# =============================================================================
# Bootstrap Process
# =============================================================================

# Step 1: Generate configuration
echo "[1/5] Generating Talos configuration..."
talosctl gen config "${CLUSTER_NAME}" "https://${VIP}:6443" \
  --with-secrets <(sops -d secrets.sops.yaml) \
  --config-patch @patches/allow-controlplane-workloads.yaml \
  --config-patch @patches/cluster-config.yaml \
  --config-patch @patches/local-path-provisioner.yaml \
  --config-patch @patches/machine-network-common.yaml \
  --config-patch @patches/metrics-server.yaml \
  --config-patch @patches/ntp.yaml \
  --config-patch-control-plane @patches/vip.yaml \
  --output rendered/

echo "✓ Configuration generated"
echo ""

# Step 2: Apply configuration to nodes
echo "[2/5] Applying configuration to nodes..."
NODES_COUNT=0
for node in "${NODES[@]}"; do
  NODE_FILE="${node%%:*}"
  NODE_IP="${node##*:}"

  printf "Apply configuration to node %s (%s)? [yes|\033[1mno\033[0m] " "${NODE_IP}" "${NODE_FILE}"
  read -r

  if [ "$REPLY" = "yes" ]; then
    echo "  → Applying to ${NODE_IP} (${NODE_FILE})..."
    talosctl apply-config --insecure --nodes "${NODE_IP}" --file rendered/controlplane.yaml --config-patch "@${NODE_FILE}"
    ((NODES_COUNT++))
  fi
done

if [ "$NODES_COUNT" = 0 ]; then
  echo "No nodes confirmed. Quitting."
  exit 0
fi

echo "✓ Configuration applied to all confirmed nodes"
echo ""

# Step 3: Wait for all nodes to be ready
echo "[3/5] Waiting for all nodes to initialize..."
if ! talosctl health --nodes "$(IFS=,; echo "${NODE_IPS[*]}")" --wait-timeout 5m; then
  echo "Error: Timed out after 5 minutes waiting for nodes to become healthy." > &2
  exit 1
fi
echo "✓ All nodes are ready"
echo ""

# Step 4: Bootstrap Kubernetes
echo "[4/5] Bootstrapping Kubernetes..."
export TALOSCONFIG="${SCRIPT_DIR}/rendered/talosconfig"
talosctl config endpoint "${VIP}"
talosctl bootstrap --nodes "${VIP}"

echo "✓ Kubernetes bootstrapped"
echo ""
echo "Waiting for cluster health..."
talosctl health --wait-timeout 5m --nodes "${VIP}" || echo "⚠ Health check timeout (cluster may still be initializing)"
echo ""

# Step 5: Generate kubeconfig
echo "[5/5] Generating kubeconfig..."
talosctl kubeconfig --nodes "${VIP}" --force

echo "✓ Kubeconfig generated"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bootstrap Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Verify cluster:"
echo "  kubectl get nodes"
echo ""
echo "Next: Bootstrap Flux CD (see README.md)"
echo ""
