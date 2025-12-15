# Beehive 🐝

[![Talos](https://img.shields.io/badge/Talos-v1.11.5-FF7300?logo=talos&logoColor=FF7300&labelColor=1a1a1a&style=for-the-badge)](https://talos.dev)&emsp;
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.3-326CE5?logo=kubernetes&logoColor=326CE5&labelColor=1a1a1a&style=for-the-badge)](https://kubernetes.io)&emsp;
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
│   │   ├── crd/                                # Helm charts (cert-manager, traefik, etc.)
│   │   └── config/                             # Configuration CRs (ClusterIssuer, IPAddressPool, etc.)
│   │                                           # ⚠️ SOPS decryption enabled here
│   └── apps/
│       └── <namespace>/<app>/                  # Application deployments
│           ├── deployment.yaml
│           └── kustomization.yaml
│
├── 📂 talos/                                   # Talos machine configuration
│   ├── secrets.sops.yaml                       # Encrypted Talos cluster secrets
│   ├── common.patches.yaml                     # Common patches (all nodes)
│   ├── vip.yaml                                # VIP configuration
│   └── queen-and-bee-01.yaml                   # Node-specific patches
│
├── 📂 .devcontainer/                           # VSCode DevContainer setup
│   ├── Dockerfile                              # Alpine + talosctl, sops, age, kustomize
│   └── devcontainer.json                       # Auto-mounts age key from host
│
└── .sops.yaml                                  # SOPS encryption rules
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

```bash
cd talos/

# Generate Talos machine configs
talosctl gen config <CLUSTER_NAME> https://192.168.178.10:6443 \
  --with-secrets <(sops -d secrets.sops.yaml) \
  --config-patch @patches/allow-controlplane-workloads.yaml \
  --config-patch @patches/cluster-config.yaml \
  --config-patch @patches/local-path-provisioner.yaml \
  --config-patch @patches/machine-network-common.yaml \
  --config-patch @patches/metrics-server.yaml \
  --config-patch @patches/ntp.yaml \
  --config-patch-control-plane @patches/vip.yaml \
  --output rendered/

# Apply config to node (replace <NODE_IP> for every node)
talosctl apply-config --insecure \
  --nodes <NODE_IP> \
  --file ./rendered/controlplane.yaml \
  --config-patch '@./queen-and-bee-01.yaml'

# Set endpoints for talosctl
talosctl config endpoint <NODE_IP>...

# Bootstrap Kubernetes (wait for node to be ready first)
talosctl bootstrap --talosconfig ./rendered/talosconfig --nodes <NODE_IP>

# Retrieve kubeconfig
talosctl kubeconfig --talosconfig ./rendered/talosconfig \
  --nodes <NODE_IP> \
  --endpoints <NODE_IP>

# Verify cluster is up
kubectl get nodes
```

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
