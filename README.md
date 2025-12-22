# Beehive 🐝

[![Talos](https://img.shields.io/badge/Talos-v1.12.0-FF7300?logo=talos&logoColor=FF7300&labelColor=1a1a1a&style=for-the-badge)](https://talos.dev)&emsp;
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.0-326CE5?logo=kubernetes&logoColor=326CE5&labelColor=1a1a1a&style=for-the-badge)](https://kubernetes.io)&emsp;
[![Flux](https://img.shields.io/badge/Flux-v2.7.5-5468FF?logo=flux&logoColor=5468FF&labelColor=1a1a1a&style=for-the-badge)](https://fluxcd.io)

A declarative, GitOps-managed Kubernetes homelab running on Talos Linux. All infrastructure and applications are defined in this repository—after initial bootstrap, changes are made exclusively through Git commits.

## 📋 Principles

- Declarative configuration (infrastructure as code)
- Git as the single source of truth
- Automated reconciliation (push to main = deployed)
- Encrypted secrets at rest (never commit plaintext)

## 🖥️ Hardware

| Device         | Role                   | CPU                        | RAM  | Storage    |
| -------------- | ---------------------- | -------------------------- | ---- | ---------- |
| Dell Wyse 5070 | Control Plane & Worker | Intel Pentium Silver J5005 | 16GB | 256GB NVMe |

## 🏗️ Repository Structure

```
📂 beehive/
│
├── 📂 kubernetes/
│   ├── flux/config/                            # Flux bootstrap & Kustomizations
│   │   ├── flux-system/                        # Auto-generated Flux components
│   │   ├── infrastructure.fluxomization.yaml
│   │   └── apps.fluxomization.yaml
│   │
│   ├── infrastructure/
│   │   ├── crd/                                    # Helm charts (cert-manager, traefik, etc.)
│   │   └── config/                                 # Configuration CRs (ClusterIssuer, IPAddressPool, etc.)
│   │                                               # ⚠️ SOPS decryption enabled here
│   └── apps/
│       └── <namespace>/<app>/                      # Application deployments
│           ├── deployment.yaml
│           └── kustomization.yaml
│
├── 📂 talos/                                       # Talos machine configuration
│   ├── bootstrap-multi-node.sh                     # Automated cluster bootstrap script
│   ├── secrets.sops.yaml                           # Encrypted Talos cluster secrets
│   ├── version.yaml                                # Talos Linux version specification
│   ├── nodes/                                      # Node-specific configurations
│   │   └── controlplane/                           # Control plane node definitions
│   │       ├── queen-and-bee-01.yaml               # Physical node config
│   │       ├── virtualbox-01.yaml                  # Virtual node 1
│   │       └── virtualbox-02.yaml                  # Virtual node 2
│   ├── patches/                                    # Configuration patches (all nodes)
│   │   ├── allow-controlplane-workloads.yaml       # Enable pod scheduling on CP
│   │   ├── allow-controlplane-loadbalancer.yaml    # Enable loadbalancer scheduling on CP
│   │   ├── cluster-config.yaml                     # Cluster network settings
│   │   ├── machine-network-common.yaml             # Common network config
│   │   ├── metrics-server.yaml                     # Metrics server deployment
│   │   ├── ntp.yaml                                # NTP time sync
│   │   └── vip.yaml                                # Virtual IP configuration
│   └── rendered/                                   # Generated configs (output)
│       ├── controlplane.yaml                       # Generated CP config
│       ├── worker.yaml                             # Generated worker config
│       └── talosconfig                             # Talos API client config
│
├── 📂 .devcontainer/                               # VSCode DevContainer setup
│   ├── Dockerfile                                  # Alpine + talosctl, sops, age, kustomize
│   └── devcontainer.json                           # Auto-mounts age key from host
│
└── .sops.yaml                                      # SOPS encryption rules
```

**Dependency Flow:**

Flux reconciles resources in strict order:

```
flux-system
  ↓
infrastructure-crds     (HelmReleases for cert-manager, traefik, metallb, etc.)
  ↓
infrastructure-config   (ClusterIssuers, Certificates, etc. — SOPS decryption enabled)
  ↓
apps                    (Application workloads)
```

## 🔐 Secret Management (Critical!)

All secrets are encrypted using **SOPS with age encryption** before committing to Git.

### ⚠️ Important Rules

1. **Never commit plaintext secrets.** Files containing sensitive data must use the `.sops.yaml` suffix (e.g., `secret.sops.yaml`).
2. The age key must exist in the cluster as a Kubernetes secret before Flux can decrypt anything.
3. The sops configuration (containing field matching rules among others) can be found in [.sops.yaml](.sops.yaml).


The public age key is committed to the repo. The private key **must** be stored securely:
- **On your workstation:** `~/.config/sops/age/keys.txt` (or `%USERPROFILE%\.config\sops\age\keys.txt` on Windows)
- **In the cluster:** As a Kubernetes secret named `sops-age` in the `flux-system` namespace

### Creating/Editing Secrets

```bash
# Create/Edit encrypted secret (opens in $EDITOR, (re-)encrypts on close)
sops kubernetes/apps/default/podinfo/mysupersecret.secret.sops.yaml
```

## 🚀 Bootstrap (From Zero to Running Cluster)

### Prerequisites

Install these tools on your workstation:
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/) — Talos CLI
- [kubectl](https://kubernetes.io/docs/tasks/tools/) — Kubernetes CLI
- [flux](https://fluxcd.io/flux/installation/) — Flux CLI
- [sops](https://github.com/getsops/sops) — Secret encryption
- [age](https://github.com/FiloSottile/age) — Encryption keys

**Or use the devcontainer!**

### 1️⃣ Generate Age Key Pair (First-Time Setup)

```bash
# Generate age key pair
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Show public key (add to .sops.yaml if not already present)
age-keygen -y ~/.config/sops/age/keys.txt
```

### 2️⃣ Bootstrap Talos Linux

The `bootstrap-multi-node.sh` script automates the entire Talos cluster setup process.

```bash
cd talos/

# Bootstrap cluster with control plane nodes
# Syntax: ./bootstrap-multi-node.sh -c <node_file>:<current_ip> ... [-w <worker_file>:<current_ip> ...] <cluster_name>

# Example 1: Single control plane node (testing/homelab)
./bootstrap-multi-node.sh \
  -c nodes/controlplane/queen-and-bee-01.yaml:192.168.178.158 \
  beehive

# Example 2: High-availability cluster (3 control planes + 2 workers)
./bootstrap-multi-node.sh \
  -c nodes/controlplane/queen-and-bee-01.yaml:192.168.178.158 \
  -c nodes/controlplane/virtualbox-01.yaml:192.168.178.159 \
  -c nodes/controlplane/virtualbox-02.yaml:192.168.178.160 \
  -w nodes/worker/worker-01.yaml:192.168.178.161 \
  -w nodes/worker/worker-02.yaml:192.168.178.162 \
  beehive

# The script will:
# [1/6] Generate Talos configurations (applies all patches)
# [2/6] Apply configuration to control plane nodes (with confirmation prompts)
# [3/6] Wait for control plane nodes to initialize (etcd readiness)
# [4/6] Bootstrap Kubernetes on first control plane
# [5/6] Apply configuration to worker nodes (if any)
# [6/6] Generate kubeconfig

# Verify cluster is up
kubectl get nodes
```

**Script Features:**
- Reads VIP and final IPs automatically from node YAML files
- Interactive confirmation before applying configs to each node
- Validates cluster health at each step
- Exports `TALOSCONFIG` automatically
- Supports single-node and multi-node clusters

### 3️⃣ Bootstrap Flux CD

```bash
# Create SOPS age secret in cluster (CRITICAL: Do this BEFORE bootstrapping Flux)
kubectl create namespace flux-system
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file age.agekey=${HOME}/.config/sops/age/keys.txt

# Bootstrap Flux (replace placeholders)
flux bootstrap github \
  --owner=<GITHUB_USERNAME> \
  --repository=<REPO_NAME> \
  --branch=main \
  --path=kubernetes/flux/config \
  --personal

# Verify Flux reconciliation
flux get kustomizations
flux get helmreleases -A
```

## 🛠️ Daily Operations

### Add a New Application

```bash
# 1. Create directory structure
mkdir -p kubernetes/apps/default/myapp

# 2. Create Kubernetes manifests
cat <<EOF > kubernetes/apps/default/myapp/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 3. Create Kustomization
cat <<EOF > kubernetes/apps/default/myapp/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
EOF

# 4. Commit and push
git add kubernetes/apps/default/myapp/
git commit -m "feat(apps): add myapp"
git push

# 5. Wait for Flux to reconcile (or force it)
flux reconcile kustomization apps --with-source
```

## 🧰 Development Environment

### Option 1: Devcontainer (Recommended)

The repository includes a devcontainer with all required tools pre-installed.

```bash
# 1. Open in VSCode
code .

# 2. Command Palette (Ctrl+Shift+P): "Dev Containers: Reopen in Container"

# 3. Tools available:
#    - talosctl, kubectl, flux, sops, age, kustomize, git
#    - Age key auto-mounted from %USERPROFILE%\.config\sops\age\keys.txt
```

### Option 2: Local Installation

Install the tools listed in [Prerequisites](#prerequisites) manually.
