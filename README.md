# Pluto Cluster 🪐

High-Availability Kubernetes (K3s) GitOps & Workload Repository for the Pluto cluster.

📖 **Documentation**: Explore the **[Documentation Hub](docs/README.md)** • **[Setup & Operations Guide](docs/SETUP_GUIDE.md)** • **[Secrets & Encryption Guide](docs/SECRETS_GUIDE.md)** • **[Solar Fleet Documentation](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster.html)**

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
    ├── home-assistant/        # Smart home automation server
    └── arr/                   # Servarr media automation + qBittorrent (Surfshark WireGuard VPN)
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

3. **Configure Secrets via NixOS (Agenix)**:
   Secrets for workloads in this cluster are **100% managed and encrypted via Nix (Agenix)** in [`solar`](https://github.com/Apollo-sudo767/solar) and [`solar-secrets`](https://github.com/Apollo-sudo767/solar-secrets):
   - `k3s-token.age` -> Cluster join token for HA control-plane.
   - `playit-secret.age` -> Injected automatically into the `games` namespace as Kubernetes secret `playit-secret`.
   - `cloudflared-credentials.age` -> Injected automatically into the `cloudflared` namespace as Kubernetes secret `cloudflared-credentials`.
   - `surfshark-vpn.age` -> Injected automatically into the `media` namespace as Kubernetes secret `surfshark-vpn-secret` for Gluetun WireGuard.

---

## 🔒 Secrets & Security Architecture

> [!NOTE]
> There are **no plaintext secrets or secret templates stored in this GitOps repository**.
> All cluster credentials are encrypted with Age keys in your private secrets flake and synced directly into Kubernetes namespaces on boot by NixOS via `k3s-secrets-sync.service` on the `pluto` control plane.

📖 **For exact instructions on creating, encrypting, and verifying each secret, see the [Secrets Provisioning & Encryption Guide](docs/SECRETS_GUIDE.md).**


