# Pluto Cluster 🪐

High-Availability Kubernetes (K3s) GitOps & Workload Repository for the Pluto cluster.

📖 **Documentation**: **[Venus ➔ Pluto Transfer Runbook](TRANSFER.md)** • **[Solar Fleet Documentation](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster)** • **[Setup Guide](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster/setup)** • **[Secrets Guide](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster/secrets)** • **[Migration Runbook](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster/migration)**

---

## 🏛️ Architecture Overview

The Pluto cluster runs a 3-node High-Availability control plane powered by an embedded etcd quorum, with NixOS compute nodes managed in [`solar`](https://github.com/Apollo-sudo767/solar):

| Node | Namesake | Hardware | Role | K3s Node Label |
| :--- | :--- | :--- | :--- | :--- |
| **`hydra`** | Moon of Pluto (Hydra) | Lenovo ThinkCentre M920q Tiny (i5-8500T, 24GB RAM) | Bootstrap Master (`clusterInit = true`) | `gpu.vendor=intel` |
| **`styx`** | Moon of Pluto (Styx) | Lenovo ThinkPad T14 Gen 2 (16GB RAM) | Control-Plane Master (joins `hydra`) | Battery UPS |
| **`pluto`** | Dwarf Planet Pluto | Beelink EQR5 (Ryzen 7 5825U, 32GB RAM) | Control-Plane Master (joins `hydra`) | `node.type=compute` |

### 💾 Progressive Storage Architecture
Storage evolves across 3 phases as the physical fleet is deployed:
1. **Phase 1 (Local Testing)**: Temporary NFS hosted on **`hydra`** (`/persist/kubernetes/storage`). Enables local testing of the cluster with 1 node.
2. **Phase 2 (Pluto Active)**: Storage shifts to **`pluto`** (`/persist/kubernetes/storage`) to take full advantage of Pluto's high-capacity NVMe drive and Ryzen 7 CPU for game servers.
3. **Phase 3 (Final Target)**: All persistent volumes migrate to **`sol`** ([Central Fleet ZFS NAS](https://github.com/Apollo-sudo767/solar)) at `sol.local:/tank/k3s-volumes`.

Dynamic provisioning is handled by `nfs-subdir-external-provisioner` (`infrastructure/nfs-provisioner/`) under the default StorageClass `nfs-client`.

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
    ├── home-assistant/        # Smart home automation server (Active)
    ├── joplin/                # Joplin note synchronization server & PostgreSQL (Active)
    ├── zotero/                # Zotero WebDAV attachment sync server & Nginx proxy (Active)
    ├── tf2/                   # Team Fortress 2 dedicated server (Active)
    ├── minecraft/             # Paper / Modpack Minecraft server (Active, playit-agent)
    ├── factorio/              # Factorio multiplayer server (Active)
    ├── jellyfin/              # Jellyfin media server (Disabled until Sol NAS)
    └── arr/                   # Servarr media automation (Disabled until Sol NAS)
```

---

## 🚀 Deployment & Installation Runbook

### Phase 1: Deploy Hydra (Bootstrap Master)

Hydra is the physical machine arriving locally first. You can install it directly using the **Solar Live Installer USB** (`sudo solar-install`) or manually from a standard **NixOS Minimal Live USB**:

1. **Boot Hydra from a Live USB** and connect to the network.

2. **Partition and Format via Disko**:
   ```bash
   sudo nix run github:nix-community/disko -- --mode zap-create-mount --flake "github:Apollo-sudo767/solar#hydra"
   ```

3. **Provision Persistent SSH Host Key**:
   ```bash
   sudo mkdir -p /mnt/persist/etc/ssh
   sudo ssh-keygen -t ed25519 -f /mnt/persist/etc/ssh/ssh_host_ed25519_key -N "" -C "root@hydra"
   sudo chmod 600 /mnt/persist/etc/ssh/ssh_host_ed25519_key
   cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
   ```
   *(On your workstation, save this key to `solar-secrets/hosts/hydra.pub`, run `s-rekey`, and push to GitHub).*

4. **Install NixOS Closure & Reboot**:
   ```bash
   sudo nixos-install --flake "github:Apollo-sudo767/solar#hydra" --no-root-password
   sudo reboot
   ```

3. **Verify Hydra on Boot**:
   ```bash
   ssh apollo@<hydra-ip>
   sudo kubectl get nodes -o wide
   showmount -e localhost  # Verifies /persist/kubernetes/storage NFS export
   ```

4. **Apply Pluto-Cluster Workloads**:
   ```bash
   git clone https://github.com/Apollo-sudo767/pluto-cluster.git
   cd pluto-cluster
   sudo kubectl apply -k .
   ```

### Phase 2: Join Styx (The Battery Laptop)

Once Hydra is online, bring Styx into the cluster:
```bash
# On Styx (or via remote deploy from mars):
sudo nixos-rebuild switch --flake "github:Apollo-sudo767/solar#styx"
```
Styx joins `https://hydra:6443` using the synced `k3s-token` and establishes 2-node HA.

### Phase 3: Transition Venus $\rightarrow$ Pluto & Cut Over Storage

When you travel to the remote location where `venus` is hosted:
1. Rebuild `venus` as `pluto`:
   ```bash
   sudo nixos-rebuild switch --flake "github:Apollo-sudo767/solar#pluto"
   ```
2. Once Pluto joins the cluster, copy existing storage from Hydra to Pluto:
   ```bash
   sudo rsync -avz /persist/kubernetes/storage/ root@pluto:/persist/kubernetes/storage/
   ```
3. Point `infrastructure/nfs-provisioner/deployment.yaml` to `pluto`:
   ```yaml
   - name: NFS_SERVER
     value: "pluto"
   ```
4. Commit and push: `kubectl apply -k .`

---

## 🔒 Secrets & Security Architecture

> [!NOTE]
> There are **no plaintext secrets or secret templates stored in this GitOps repository**.
> All cluster credentials are encrypted with Age keys in [`solar-secrets`](https://github.com/Apollo-sudo767/solar-secrets) and synced directly into Kubernetes namespaces on boot by NixOS via `k3s-secrets-sync.service` on the control plane.

📖 **For exact instructions on creating, encrypting, and verifying each secret, see the [Secrets Provisioning & Encryption Guide](https://apollo-sudo767.github.io/solar/fleet/pluto-cluster/secrets).**


