#!/usr/bin/env bash
# Talos Linux Multi-Node Cluster Bootstrap
# Handles control plane + worker node clusters
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# =============================================================================
# Usage & Argument Parsing
# =============================================================================

usage() {
  echo "Usage: $0 -c cp_node:current_ip ... [-w worker_node:current_ip ...] <cluster_name>"
  echo ""
  echo "Arguments:"
  echo "  -c node:ip        Control plane node (required, min 1, recommended 3)"
  echo "  -w node:ip        Worker node (optional, repeatable)"
  echo "  <cluster_name>    Name of the cluster (required)"
  echo ""
  echo "Examples:"
  echo "  # 3 CP nodes + 2 workers"
  echo "  $0 -c nodes/controlplane/01.yaml:10.0.0.11 \\"
  echo "     -c nodes/controlplane/02.yaml:10.0.0.12 \\"
  echo "     -c nodes/controlplane/03.yaml:10.0.0.13 \\"
  echo "     -w nodes/worker/01.yaml:10.0.0.21 \\"
  echo "     -w nodes/worker/02.yaml:10.0.0.22 \\"
  echo "     production"
  echo ""
  echo "  # 1 CP node only (testing)"
  echo "  $0 -c nodes/controlplane/01.yaml:10.0.0.11 dev-cluster"
  exit 1
}

# Variables
CP_NODES=()
WORKER_NODES=()
CP_APPLY_IPS=()
CP_FINAL_IPS=()
CP_FILES=()
WORKER_APPLY_IPS=()
WORKER_FINAL_IPS=()
WORKER_FILES=()

# Parse arguments
while getopts "c:w:h" opt; do
  case "$opt" in
    c) CP_NODES+=("$OPTARG");;
    w) WORKER_NODES+=("$OPTARG");;
    h|?) usage;;
  esac
done

shift $((OPTIND-1))
[ $# -eq 0 ] && usage

CLUSTER_NAME="$1"

# =============================================================================
# Validation
# =============================================================================

# Read VIP
VIP=$(yq -e '.machine.network.interfaces[0].vip.ip' patches/vip.yaml) || {
  echo "Error: Could not read VIP from patches/vip.yaml"
  exit 1
}

# Require at least 1 control plane node
[ ${#CP_NODES[@]} -eq 0 ] && {
  echo "Error: At least one control plane node required (-c flag)"
  usage
}

# Warn if less than 3 CP nodes
if [ ${#CP_NODES[@]} -lt 3 ]; then
  echo "⚠ Warning: You have ${#CP_NODES[@]} control plane nodes. For production, 3+ recommended (etcd quorum)."
  echo ""
fi

# Extract control plane node information
for node_entry in "${CP_NODES[@]}"; do
  NODE_FILE="${node_entry%%:*}"
  CURRENT_IP="${node_entry##*:}"
  FINAL_IP=$(yq -e 'select(di == 0) | .machine.network.interfaces[0].addresses[0]' "${NODE_FILE}" | cut -d'/' -f1) || {
    echo "Error: Could not read static IP from ${NODE_FILE}"
    exit 1
  }

  CP_FILES+=("${NODE_FILE}")
  CP_APPLY_IPS+=("${CURRENT_IP}")
  CP_FINAL_IPS+=("${FINAL_IP}")
done

# Extract worker node information
for node_entry in "${WORKER_NODES[@]}"; do
  NODE_FILE="${node_entry%%:*}"
  CURRENT_IP="${node_entry##*:}"
  FINAL_IP=$(yq -e 'select(di == 0) | .machine.network.interfaces[0].addresses[0]' "${NODE_FILE}" | cut -d'/' -f1) || {
    echo "Error: Could not read static IP from ${NODE_FILE}"
    exit 1
  }

  WORKER_FILES+=("${NODE_FILE}")
  WORKER_APPLY_IPS+=("${CURRENT_IP}")
  WORKER_FINAL_IPS+=("${FINAL_IP}")
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Talos Multi-Node Bootstrap: ${CLUSTER_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cluster:         ${CLUSTER_NAME}"
echo "  VIP:             ${VIP}"
echo "  Control Planes:  ${#CP_FILES[@]}"
for i in "${!CP_FILES[@]}"; do
  echo "    → ${CP_FINAL_IPS[$i]} (${CP_FILES[$i]})"
done
if [ ${#WORKER_FILES[@]} -gt 0 ]; then
  echo "  Workers:         ${#WORKER_FILES[@]}"
  for i in "${!WORKER_FILES[@]}"; do
    echo "    → ${WORKER_FINAL_IPS[$i]} (${WORKER_FILES[$i]})"
  done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# =============================================================================
# Bootstrap Process
# =============================================================================

# Step 1: Generate configurations
echo "[1/6] Generating Talos configurations..."
talosctl gen config "${CLUSTER_NAME}" "https://${VIP}:6443" \
  --with-secrets <(sops -d secrets.sops.yaml) \
  --config-patch @patches/allow-controlplane-workloads.yaml \
  --config-patch @patches/cluster-config.yaml \
  --config-patch @patches/machine-network-common.yaml \
  --config-patch @patches/metrics-server.yaml \
  --config-patch @patches/ntp.yaml \
  --config-patch-control-plane @patches/vip.yaml \
  --output rendered/

echo "✓ Configurations generated (controlplane.yaml, worker.yaml)"
echo ""

# Step 2: Apply configuration to control plane nodes
echo "[2/6] Applying configuration to control plane nodes..."
CP_COUNT=0
for i in "${!CP_FILES[@]}"; do
  NODE_FILE="${CP_FILES[$i]}"
  APPLY_IP="${CP_APPLY_IPS[$i]}"
  FINAL_IP="${CP_FINAL_IPS[$i]}"

  printf "Apply to CP node %s (→ %s)? [yes|\033[1mno\033[0m] " "${APPLY_IP}" "${FINAL_IP}"
  read -r

  if [ "$REPLY" = "yes" ]; then
    echo "  → Applying to ${APPLY_IP} (${NODE_FILE})..."
    talosctl apply-config --insecure --nodes "${APPLY_IP}" --file rendered/controlplane.yaml --config-patch "@${NODE_FILE}"
    ((++CP_COUNT))
  else
    # Remove declined node from arrays
    unset 'CP_FILES[$i]'
    unset 'CP_APPLY_IPS[$i]'
    unset 'CP_FINAL_IPS[$i]'
  fi
done

[ "$CP_COUNT" = 0 ] && { echo "No control plane nodes confirmed. Quitting."; exit 0; }

echo "✓ Configuration applied to ${CP_COUNT} control plane node(s)"
echo ""

export TALOSCONFIG="${SCRIPT_DIR}/rendered/talosconfig"
talosctl config endpoint "${CP_FINAL_IPS[@]}"

# Step 3: Wait for control plane nodes to be ready
echo "[3/6] Waiting for control plane nodes to initialize..."
# for node_ip in "${CP_FINAL_IPS[@]}"; do
  # echo "  Checking ${node_ip}..."
until talosctl service etcd --nodes "${CP_FINAL_IPS[*]}" 2>/dev/null | grep -q "STATE.*Preparing\|STATE.*Waiting"; do
  sleep 5
done
  # echo "  ✓ ${node_ip} etcd is ready"
# done
echo "✓ All control plane nodes ready"
echo ""

# Step 4: Bootstrap Kubernetes on first control plane
echo "[4/6] Bootstrapping Kubernetes on first control plane..."
echo "  Using: ${CP_FINAL_IPS[0]}"
talosctl bootstrap --nodes "${CP_FINAL_IPS[0]}"

echo "✓ Kubernetes bootstrapped"
echo ""
echo "Waiting for cluster to stabilize and NTP to sync..."
sleep 5
echo "Waiting for control plane cluster health..."
talosctl health --wait-timeout 5m --nodes "${CP_FINAL_IPS[*]}"
echo ""

# Step 5: Apply configuration to worker nodes (if any)
if [ ${#WORKER_FILES[@]} -gt 0 ]; then
  echo "[5/6] Applying configuration to worker nodes..."
  WORKER_COUNT=0
  for i in "${!WORKER_FILES[@]}"; do
    NODE_FILE="${WORKER_FILES[$i]}"
    APPLY_IP="${WORKER_APPLY_IPS[$i]}"
    FINAL_IP="${WORKER_FINAL_IPS[$i]}"

    printf "Apply to worker %s (→ %s)? [yes|\033[1mno\033[0m] " "${APPLY_IP}" "${FINAL_IP}"
    read -r

    if [ "$REPLY" = "yes" ]; then
      echo "  → Applying to ${APPLY_IP} (${NODE_FILE})..."
      talosctl apply-config --insecure --nodes "${APPLY_IP}" --file rendered/worker.yaml --config-patch "@${NODE_FILE}"
      ((++WORKER_COUNT))
    else
      # Remove declined node from arrays
      unset 'WORKER_FILES[$i]'
      unset 'WORKER_APPLY_IPS[$i]'
      unset 'WORKER_FINAL_IPS[$i]'
    fi
  done

  echo "✓ Configuration applied to ${WORKER_COUNT} worker node(s)"
  echo ""

  # Wait for workers to join
  echo "Waiting for worker nodes to join cluster..."
  # for worker_ip in "${WORKER_FINAL_IPS[@]}"; do
  #   echo "  Checking ${worker_ip}..."
  talosctl health --wait-timeout 5m --nodes "${WORKER_FINAL_IPS[*]}" || echo "    ⚠ Health check timeout"
  # done
  # echo ""
else
  echo "[5/6] No worker nodes specified, skipping..."
  echo ""
fi

# Step 6: Generate kubeconfig
echo "[6/6] Generating kubeconfig..."
echo "  Using first control plane: ${CP_FINAL_IPS[0]}"
talosctl kubeconfig --nodes "${CP_FINAL_IPS[0]}" --force

echo "✓ Kubeconfig generated"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Multi-Node Bootstrap Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster Summary:"
echo "  Control Planes: ${#CP_FINAL_IPS[@]}"
for ip in "${CP_FINAL_IPS[@]}"; do
  echo "    - ${ip}"
done
if [ ${#WORKER_FINAL_IPS[@]} -gt 0 ]; then
  echo "  Workers:        ${#WORKER_FINAL_IPS[@]}"
  for ip in "${WORKER_FINAL_IPS[@]}"; do
    echo "    - ${ip}"
  done
fi
echo ""
echo "Set environment variable in your shell:"
echo "  export TALOSCONFIG=\"${SCRIPT_DIR}/rendered/talosconfig\""
echo ""
echo "Verify cluster:"
echo "  kubectl get nodes"
echo "  talosctl health --nodes ${CP_FINAL_IPS[0]}"
echo ""
echo "Next: Bootstrap Flux CD (see README.md)"
echo ""
