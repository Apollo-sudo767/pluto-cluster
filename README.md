# Pluto Cluster 🪐

High-Availability Kubernetes (K3s) GitOps & Workload Repository for the Pluto cluster.

---

## 🏛️ Architecture Overview

The Pluto cluster runs a 3-node High-Availability control plane powered by an embedded etcd quorum, with NixOS compute nodes managed in [`solar`](https://github.com/Apollo-sudo767/solar):

| Node | Namesake | Hardware | Role | K3s Node Label |
| :--- | :--- | :--- | :--- | :--- |
| **`pluto`** | Dwarf Planet Pluto | Beelink EQR5 (Ryzen 7 5825U, 32GB RAM) | Bootstrap Master (`clusterInit`) | `node.type=compute` |
| **`styx`** | Moon of Pluto (Styx) | Lenovo ThinkPad T14 Gen 2 (16GB RAM) | Control-Plane Master | Server peer |
| **`hydra`** | Moon of Pluto (Hydra) | Lenovo ThinkCentre M920q Tiny (i5-8500T, 16GB RAM) | Control-Plane Master | `gpu.vendor=intel` |

### 💾 Dynamic Storage Foundation
All persistent storage in this cluster is backed dynamically by **Sol** ([Central Fleet ZFS NAS](https://github.com/Apollo-sudo767/solar)):
- **NFS Endpoint**: `sol.local:/tank/k3s-volumes`
- **Dynamic Provisioner**: `nfs-subdir-external-provisioner` (`infrastructure/nfs-provisioner/`)
- **Default StorageClass**: `nfs-client` (marked as cluster default)

---

## 📁 Repository Structure

```text
pluto-cluster/
├── bootstrap.sh               # Automated Flux CD bootstrap helper
├── clusters/
│   └── pluto/                 # Flux CD cluster definition & synchronizer
│       ├── flux-system/       # GitRepository & Flux Kustomization
│       ├── infrastructure.yaml# Kustomization for infrastructure components
│       └── apps.yaml          # Kustomization for user applications
├── infrastructure/
│   ├── nfs-provisioner/       # Dynamic NFS storage provisioner (nfs-client)
│   └── cloudflared/           # Cloudflare Tunnel for secure HTTPS web ingress
└── apps/
    ├── minecraft/             # Paper Minecraft server (8GB RAM, Beelink, playit-agent)
    ├── jellyfin/              # Jellyfin media server (QuickSync hardware video transcoding)
    └── home-assistant/        # Smart home automation server
```

---

## 🚀 Quickstart & Bootstrapping

1. **Connect to your cluster**:
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get nodes
   ```

2. **Bootstrap Flux CD**:
   ```bash
   ./bootstrap.sh
   ```

3. **Configure Secrets**:
   Before deploying workloads, populate the required credentials:
   - `apps/minecraft/secret.yaml`: Set `PLAYIT_SECRET_KEY`.
   - `infrastructure/cloudflared/secret.yaml`: Set `credentials.json` or `TUNNEL_TOKEN`.

---

## 🔒 Secrets & Security Best Practices

> [!IMPORTANT]
> The secret manifests in this repository contain placeholder values. For production GitOps, encrypt these manifests using **SOPS** (`sops -e -i secret.yaml`) with age keys or use **Sealed Secrets** / **External Secrets Operator** before pushing to public repositories.
