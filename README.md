# Beehive

[![Talos](https://img.shields.io/badge/OS-Talos_Linux-FF7300?logo=talos&logoColor=white&style=for-the-badge)](https://talos.dev)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5?logo=kubernetes&logoColor=white&style=for-the-badge)](https://kubernetes.io)
[![Flux](https://img.shields.io/badge/GitOps-FluxCD-5468FF?logo=flux&logoColor=white&style=for-the-badge)](https://fluxcd.io)


## Overview

This repository contains the declarative configuration for my single-node Kubernetes homelab. The entire stack runs on a low-power mini PC with Talos Linux as the immutable operating system. All cluster workloads are managed via GitOps using Flux CD—after initial setup, changes are made exclusively through this Git repository.

### Principles

- **Declarative** — Infrastructure and apps defined as YAML
- **GitOps** — Git is the single source of truth
- **Immutable** — Talos Linux has no shell, SSH, or package manager
- **Automated** — Commits trigger automatic cluster reconciliation

## Hardware

| Device | Role | CPU | RAM | Storage |
|--------|------|-----|-----|---------|
| Dell Wyse 5070 | Control Plane & Worker Node | Intel Pentium Silber J5005 | 16GB | 256GB NVMe |

## Repository Structure

```
📂 talos/                        # Talos Linux configuration (pre-cluster)
│   ├── talconfig.yaml           # Talhelper source config
│   ├── clusterconfig/           # Generated machine configs (gitignored or encrypted)
│   └── patches/                 # Custom Talos patches
│
📂 kubernetes/                   # Flux-managed Kubernetes manifests
│
├── 📂 flux/config/
│   ├── flux-system/             # Flux bootstrap components (auto-generated)
│   ├── infrastructure.fluxomization.yaml
│   └── apps.fluxomization.yaml
│
├── 📂 infrastructure/
│   ├── controllers/             # cert-manager, ingress-nginx, etc.
│   └── configs/                 # ClusterIssuers, StorageClasses, etc.
│
└── 📂 apps/
    └── <namespace>/
        └── <app>/
            ├── deployment.yaml  # (or helmrelease.yaml)
            └── kustomization.yaml
```

### Dependency Flow

Flux reconciles resources in order via `dependsOn`:

```
flux-system ─▶ infrastructure/controllers ─▶ infrastructure/configs ─▶ apps
```

## Bootstrap

### Prerequisites

- `talosctl` — [Install Guide](https://www.talos.dev/latest/introduction/getting-started/)
- `kubectl` — [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- `flux` — [Install Guide](https://fluxcd.io/flux/installation/)
- GitHub Personal Access Token with repo permissions

### 1. Talos Linux

```powershell
# Generate common config
# With VIP: 192.168.178.10
talosctl gen config beehive https://192.168.178.10:6443 --with-secrets './talos/secrets.yaml' --config-patch '@./talos/common.patches.yaml' --config-patch-control-plane '@./talos/vip.yaml' --output ./talos/rendered/

# Apply machine config to node
talosctl apply-config --insecure --nodes <NODE_IP> --file talos/rendered/controlplane.yaml --config-patch '@./talos/queen-and-bee-01.yaml'

# Bootstrap etcd and Kubernetes
talosctl bootstrap --talosconfig talos/rendered/talosconfig --nodes <NODE_IP>

# Retrieve kubeconfig
talosctl kubeconfig --talosconfig talos/rendered/talosconfig --nodes <NODE_IP> --endpoints <NODE_IP>

# Verify
kubectl get nodes
```

### 2. Flux CD

```bash
# Set GitHub token
export GITHUB_TOKEN=<your-token>

# Bootstrap Flux
flux bootstrap github \
  --owner=<GITHUB_USERNAME> \
  --repository=<REPO_NAME> \
  --branch=main \
  --path=kubernetes/flux/config \
  --personal

# Verify
flux get kustomizations
```

## Secret Management

<!-- Uncomment and configure your chosen method -->

<!--
### SOPS with Age
Secrets are encrypted with SOPS using Age keys before being committed.
See: https://fluxcd.io/flux/guides/mozilla-sops/
-->

<!--
### External Secrets
Secrets are fetched from an external provider (e.g., 1Password, Vault).
See: https://external-secrets.io/
-->

## Applications

### Infrastructure

| App | Namespace | Purpose | Status |
|-----|-----------|---------|:------:|
| cert-manager | `cert-manager` | TLS certificate management | 🚧 |
| ingress-nginx | `ingress-nginx` | Ingress controller | 🚧 |
| <!-- app --> | <!-- namespace --> | <!-- purpose --> | |

### Workloads

| App | Namespace | Purpose | Status |
|-----|-----------|---------|:------:|
| --- | --- | --- | 🚧 |
| <!-- app --> | <!-- namespace --> | <!-- purpose --> | |
