# Beehive 🐝

[![Talos](https://img.shields.io/badge/Talos-v1.12.6-FF7300?logo=talos&logoColor=FF7300&labelColor=1a1a1a&style=for-the-badge)](https://talos.dev)&emsp;
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.2-326CE5?logo=kubernetes&logoColor=326CE5&labelColor=1a1a1a&style=for-the-badge)](https://kubernetes.io)&emsp;
[![Flux](https://img.shields.io/badge/Flux-v2.8.3-5468FF?logo=flux&logoColor=5468FF&labelColor=1a1a1a&style=for-the-badge)](https://fluxcd.io)

A declarative, GitOps-managed Kubernetes homelab running on Talos Linux. All infrastructure and applications are defined in this repository—after initial bootstrap, changes are made exclusively through Git commits.

## 📋 Principles

- **Declarative Configuration:** Everything as code (IaC).
- **GitOps:** Git is the single source of truth for cluster state.
- **Automated Reconciliation:** Push to `main` = deployed (Flux CD).
- **Security First:** Encrypted secrets at rest (SOPS) and API-driven OS (Talos).

## 🖥️ Hardware

| Device         | Role                   | CPU                        | RAM  | Storage                                       |
| -------------- | ---------------------- | -------------------------- | ---- | --------------------------------------------- |
| Dell Wyse 5070 | Control Plane & Worker | Intel Pentium Silver J5005 | 16GB | 256GB NVMe (ephemeral) <br/> 128GB SATA (storage) |

## 🏗️ Repository Structure

```
📂 beehive/
│
├── 📂 kubernetes/
│   ├── 📂 flux/config/                         # Flux bootstrap & Kustomizations
│   │   ├── 📂 flux-system/                     # Auto-generated Flux components
│   │   ├── apps.fluxomization.yaml             # Apps entry point
│   │   └── infrastructure.fluxomization.yaml   # Infra entry point
│   │
│   ├── 📂 infrastructure/
│   │   ├── 📂 crd/                             # HelmReleases (Traefik, Cert-Manager, etc.)
│   │   └── 📂 config/                          # Configuration CRs (ClusterIssuers, IP Pools)
│   │                                           # ⚠️ SOPS decryption enabled here
│   └── 📂 apps/
│       ├── 📂 networking/                      # Blocky, Ingress controllers
│       ├── 📂 monitoring/                      # Prometheus, Grafana
│       └── 📂 default/                         # Paperless, LanCache, etc.
│
├── 📂 talos/                                   # Talos machine configuration
│   ├── bootstrap-multi-node.sh                 # Automated cluster bootstrap script
│   ├── 📂 nodes/                               # Node-specific configurations
│   ├── 📂 patches/                             # Shared configuration patches
│
└── .sops.yaml                                  # SOPS encryption rules
```

## ⚙️ Dependency Flow

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

## 🛠️ Maintenance & Automation

- **Renovate:** Automated dependency updates for Helm charts, container images, and even Talos/Kubernetes versions (including the badges in this README!).
- **Security Scans:** GitHub Actions run periodic scans on the codebase.

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
# Example: Single control plane node (testing/homelab)
./bootstrap-multi-node.sh \
  -c nodes/controlplane/queen-and-bee-01.yaml:192.168.178.158 \
  beehive

# Example: High-availability cluster (3 control planes + 2 workers)
./bootstrap-multi-node.sh \
  -c nodes/controlplane/queen-and-bee-01.yaml:192.168.178.158 \
  -c nodes/controlplane/virtualbox-01.yaml:192.168.178.159 \
  -c nodes/controlplane/virtualbox-02.yaml:192.168.178.160 \
  -w nodes/worker/worker-01.yaml:192.168.178.161 \
  -w nodes/worker/worker-02.yaml:192.168.178.162 \
  beehive
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

# Bootstrap Flux
flux bootstrap github \
  --owner=<GITHUB_USERNAME> \
  --repository=<REPO_NAME> \
  --branch=main \
  --path=kubernetes/flux/config \
  --personal
```

## 🛠️ Daily Operations

### Add a New Application

1. Create directory structure: `mkdir -p kubernetes/apps/<namespace>/myapp`
2. Create manifests (`deployment.yaml`, `service.yaml`, etc.).
3. Create `kustomization.yaml` in the app directory.
4. Add the new directory to `kubernetes/apps/<namespace>/kustomization.yaml`.
5. Commit and push.
6. Force sync if needed: `flux reconcile kustomization apps --with-source`.

## 🧰 Development Environment

### Option 1: Devcontainer (Recommended)

The repository includes a devcontainer with all required tools.
- Open in VSCode → "Reopen in Container".
- Age key is auto-mounted from your host machine.

### Option 2: Local Installation

Install the tools listed in [Prerequisites](#prerequisites) manually.
