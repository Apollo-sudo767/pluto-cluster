# 🪐 Pluto Cluster Documentation Hub

Welcome to the technical documentation library for the **Pluto High-Availability K3s GitOps Cluster**.

This directory contains full operational runbooks, architecture diagrams, secret provisioning workflows, and troubleshooting guides for the cluster.

---

## 📚 Documentation Library

| Guide | Description | Primary Topics |
| :--- | :--- | :--- |
| **[Setup & Operations Guide](SETUP_GUIDE.md)** | End-to-end deployment, bootstrapping, and administration manual | Architecture, hardware specs, Sol NAS storage, cluster init, Flux CD GitOps, ingress, maintenance, and runbooks |
| **[Secrets & Encryption Guide](SECRETS_GUIDE.md)** | Security architecture and zero-plaintext secrets guide | Agenix rekeying, YubiKey decryption, NixOS `k3s-secrets-sync.service`, Kubernetes Secrets injection |
| **[Fleet Documentation](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster.html)** | Upstream Solar documentation for the Pluto constellation | Node hardware specs, ephemeral root filesystems, Disko layout, and central fleet integration |

---

## 🏛️ Quick Architecture Summary

```
                      ┌─────────────────────────────────────────┐
                      │       Sol (Central ZFS Storage NAS)     │
                      │       NFS: sol.local:/tank/k3s-volumes  │
                      └────────────────────┬────────────────────┘
                                           │ Dynamic NFS Storage (nfs-client)
                 ┌─────────────────────────┼─────────────────────────┐
                 │                         │                         │
                 ▼                         ▼                         ▼
   ┌──────────────────────────┐┌──────────────────────────┐┌──────────────────────────┐
   │         pluto            ││           styx           ││          hydra           │
   │   Beelink EQR5 (Ryzen)   ││   ThinkPad T14 Gen 2     ││  ThinkCentre M920q Tiny  │
   │  Bootstrap Master Node   ││   Control Plane Master   ││   Control Plane Master   │
   │    node.type=compute     ││      Battery capped      ││     gpu.vendor=intel     │
   │   Reboot: Sun 03:00      ││    Reboot: Sun 03:30     ││    Reboot: Sun 04:00     │
   └─────────────┬────────────┘└─────────────┬────────────┘└─────────────┬────────────┘
                 └───────────────────────────┼───────────────────────────┘
                                             │
                                   Embedded etcd Quorum
```

- **Quorum**: 3-node embedded etcd control plane across `pluto`, `styx`, and `hydra`.
- **GitOps**: Synchronized automatically from `main` via Flux CD.
- **Storage**: Dynamic persistent volumes via `nfs-client` backed by `sol` (or temporary `pluto` NFS).
- **Secrets**: 100% encrypted at rest in [`solar-secrets`](https://github.com/Apollo-sudo767/solar-secrets) via Agenix, synced into K3s namespaces on boot.

---

## 🧭 Navigation Index

### 1. Cluster Deployment & Bootstrapping
- [Hardware Nodes & Prerequisites](SETUP_GUIDE.md#2-prerequisites--hardware-nodes)
- [NFS Storage Foundation](SETUP_GUIDE.md#3-nixos--nas-storage-foundation-sol)
- [Quorum Initialization & Join Process](SETUP_GUIDE.md#5-cluster-bootstrapping--quorum-initialization)
- [Flux CD Bootstrapping](SETUP_GUIDE.md#6-gitops-deployment-with-flux-cd)

### 2. Secrets & Security
- [Age Encryption & Rekeying](SECRETS_GUIDE.md#1-prerequisites--directory-structure)
- [Managed Secrets Matrix](SECRETS_GUIDE.md#3-the-secrets-matrix)
- [NixOS Secrets Sync Daemon](SECRETS_GUIDE.md#4-how-nixos-synchronizes-secrets-to-k3s)
- [Verification & Troubleshooting](SECRETS_GUIDE.md#6-troubleshooting--common-pitfalls)

### 3. Networking & Workloads
- [Playit.gg Ingress for Minecraft](SETUP_GUIDE.md#playitgg-sidecar-integration)
- [Custom DNS & SRV Records](SETUP_GUIDE.md#custom-domain--dns-srv-records)
- [Cloudflare Tunnels for Web Services](SETUP_GUIDE.md#cloudflare-ingress-for-web-services)
- [Workloads Reference](SETUP_GUIDE.md#8-workloads-reference)

### 4. Day-2 Operations
- [Staggered Automated Maintenance](SETUP_GUIDE.md#9-day-2-operations--maintenance)
- [Troubleshooting & Quorum Recovery Runbook](SETUP_GUIDE.md#10-troubleshooting-runbook)

---

## 🔗 External Links

- **Main GitOps Repository**: [Apollo-sudo767/pluto-cluster](https://github.com/Apollo-sudo767/pluto-cluster)
- **Solar Fleet Flake**: [Apollo-sudo767/solar](https://github.com/Apollo-sudo767/solar)
- **Solar Online Documentation**: [Solar Documentation Book](https://apollo-sudo767.github.io/solar/)
