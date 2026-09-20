# 🪐 Pluto Cluster: Venus ➔ Hydra ➔ Pluto Complete Transfer Guide

This document is the master operational runbook for migrating all stateful workloads, game servers, databases, and persistent volumes from the standalone bare-metal NixOS server **`venus`** to the **Pluto High-Availability K3s Cluster** staged via **`hydra`**.

---

## 📑 Table of Contents

1. [Architectural Overview & Transition Strategy](#1-architectural-overview--transition-strategy)
2. [Hardware & Memory Capacity](#2-hardware--memory-capacity)
3. [Phase 1: Backup & Stash Venus State onto Hydra](#3-phase-1-backup--stash-venus-state-onto-hydra)
4. [Phase 2: Seed & Test Workloads on Hydra (Zero Risk)](#4-phase-2-seed--test-workloads-on-hydra-zero-risk)
5. [Phase 3: Wipe & Rebuild Venus as Pluto](#5-phase-3-wipe--rebuild-venus-as-pluto)
6. [Phase 4: Automatic Compute Join & Pod Scheduling](#6-phase-4-automatic-compute-join--pod-scheduling)
7. [Phase 5: Cut Over Shared NFS Storage from Hydra to Pluto](#7-phase-5-cut-over-shared-nfs-storage-from-hydra-to-pluto)
8. [Phase 6: Production Ingress Cutover & Fleet Cleanup](#8-phase-6-production-ingress-cutover--fleet-cleanup)

---

## 1. Architectural Overview & Transition Strategy

### Why Stage on Hydra First?
**`venus` and `pluto` share the exact same physical hardware** (a Beelink EQR5 mini PC). Rebuilding Venus as Pluto involves wiping the root filesystem, partitioning with Disko LUKS + Btrfs, and initializing ephemeral tmpfs impermanence.

Because the machine must be wiped to become Pluto, persistent data cannot be transferred directly between Venus and Pluto. **Hydra serves as the safe harbor and Phase 1 storage host**:

```
[ Venus (NixOS Server) ]
          │
          │ 1. Backup DBs, attachments, world saves
          ▼
[ Hydra (K3s Bootstrap Master + Phase 1 NFS Server) ]
          │
          │ 2. Seed PVCs & verify 100% of apps via Flux CD
          │ 3. Wipe & rebuild Venus as Pluto
          │ 4. Pluto joins K3s cluster (node.type=compute)
          │ 5. rsync /persist/kubernetes/storage/ from Hydra to Pluto
          ▼
[ Pluto (High-Performance Compute Node + Phase 2 NFS Server) ]
```

---

## 2. Hardware & Memory Capacity

With **Hydra equipped with 24GB RAM**, memory constraints are eliminated during staging. All workloads can run simultaneously on Hydra for testing:

| Node | Physical Hardware | Specs & Roles | Memory | Staging Role |
| :--- | :--- | :--- | :--- | :--- |
| **`hydra`** | Lenovo ThinkCentre M920q Tiny | Intel i5-8500T (6C/6T), NVMe | **24GB RAM** | K3s Bootstrap Master (`clusterInit`), Phase 1 NFS Server |
| **`styx`** | Lenovo ThinkPad T14 Gen 2 | Intel Core i5, NVMe, Battery UPS | **16GB RAM** | K3s Control-Plane Master |
| **`pluto`** *(formerly Venus)* | Beelink EQR5 | AMD Ryzen 7 5825U (8C/16T), 1TB NVMe | **32GB RAM** | Final Compute Master (`node.type=compute`), Phase 2 NFS Server |

### Hydra Memory Budget (Full Load Verification)
* K3s Control Plane & Host OS: `~1.5 GB`
* Joplin Server & PostgreSQL: `~1.5 GB`
* Zotero WebDAV & Nginx Proxy: `~0.2 GB`
* LanguageTool API: `~1.5 GB`
* Factorio Headless Server: `~2.5 GB`
* Minecraft Server (PhasMC 1.21.1 NeoForge modpack): `~12.0 GB`
* **Total Committed**: `~19.0 GB` (Leaves `~5.0 GB` safe buffer on Hydra)

---

## 3. Phase 1: Backup & Stash Venus State onto Hydra

Before touching Venus, create a temporary staging directory on Hydra and copy all persistent application data over SSH.

### Step 3.1: Prepare Staging Directory on Hydra
```bash
ssh apollo@hydra "sudo mkdir -p /persist/backup/{joplin,zotero,factorio,minecraft} && sudo chown -R apollo:users /persist/backup"
```

### Step 3.2: Backup Joplin PostgreSQL Database
On `venus`, stop Joplin to ensure transaction consistency, then create a clean SQL dump:
```bash
ssh root@venus "systemctl stop joplin-server"
ssh root@venus "sudo -u postgres pg_dump -d joplin --clean --if-exists > /tmp/joplin_backup.sql"
scp root@venus:/tmp/joplin_backup.sql apollo@hydra:/persist/backup/joplin/
```

### Step 3.3: Backup Zotero WebDAV Attachments
```bash
rsync -avzP /var/lib/zotero-webdav/zotero/ apollo@hydra:/persist/backup/zotero/
```

### Step 3.4: Backup Factorio Saves & Mods
```bash
ssh root@venus "systemctl stop factorio"
rsync -avzP /var/lib/factorio/saves/ apollo@hydra:/persist/backup/factorio/saves/

if [ -d /var/lib/factorio/mods ]; then
  rsync -avzP /var/lib/factorio/mods/ apollo@hydra:/persist/backup/factorio/mods/
fi
if [ -f /var/lib/factorio/config/server-settings.json ]; then
  rsync -avzP /var/lib/factorio/config/server-settings.json apollo@hydra:/persist/backup/factorio/server-settings.json
fi
```

### Step 3.5: Backup Minecraft Modpack Server (Dereferencing Nix Store)
> [!IMPORTANT]
> In `nix-minecraft`, mods and configs are symlinks pointing to `/nix/store/...`. You **must** pass the **`-L`** flag (`--copy-links`) to `rsync` so real files are copied instead of broken symlinks!

```bash
ssh root@venus "systemctl stop minecraft-server-no-mans-land"
rsync -avzLP /srv/minecraft/no-mans-land/ apollo@hydra:/persist/backup/minecraft/
```

---

## 4. Phase 2: Seed & Test Workloads on Hydra (Zero Risk)

Hydra's NFS provisioner automatically manages PVC directories under `/persist/kubernetes/storage/`.

### Step 4.1: Deploy Manifests via Flux CD
Ensure `apps/kustomization.yaml` has the workloads enabled:
```bash
cd ~/src/pluto-cluster
git add apps/ infrastructure/
git commit -m "feat(apps): enable joplin, zotero, factorio, and minecraft"
git push origin main

# Force immediate reconciliation on Hydra
flux reconcile kustomization apps --with-source
```

Wait for the PVCs to bind:
```bash
kubectl get pvc -A
```

### Step 4.2: Seed Persistent Data into the Bound PVCs

#### 1. Restore Joplin Database
```bash
# Wait for joplin-postgres pod to be running
kubectl wait --for=condition=ready pod -l app=joplin-postgres -n productivity --timeout=120s

# Scale down joplin-server during restore
kubectl scale deployment -n productivity joplin-server --replicas=0

# Stream database dump into postgres pod
cat /persist/backup/joplin/joplin_backup.sql | kubectl exec -i -n productivity deploy/joplin-postgres -- psql -U joplin -d joplin

# Scale joplin back up
kubectl scale deployment -n productivity joplin-server --replicas=1
```

#### 2. Seed Zotero WebDAV Files (Longhorn Volume)
```bash
# Ensure zotero pod is running with bound Longhorn volume
kubectl wait --for=condition=ready pod -l app=zotero -n productivity --timeout=120s
ZOTERO_POD=$(kubectl get pod -n productivity -l app=zotero -o jsonpath='{.items[0].metadata.name}')

# Copy backed up files directly into the Longhorn-backed mount
kubectl cp /persist/backup/zotero/. productivity/${ZOTERO_POD}:/data/zotero/
kubectl exec -n productivity ${ZOTERO_POD} -- chmod -R 0777 /data/zotero
```

#### 3. Seed Factorio Saves (NFS Volume)
```bash
kubectl scale deployment -n games factorio-server --replicas=0
FACTORIO_PVC=$(ls -d /persist/kubernetes/storage/games-factorio-data-*)
sudo rsync -avzP /persist/backup/factorio/saves/ ${FACTORIO_PVC}/saves/
if [ -d /persist/backup/factorio/mods ]; then
  sudo rsync -avzP /persist/backup/factorio/mods/ ${FACTORIO_PVC}/mods/
fi
# Fix ownership for factoriotools user (UID 845)
sudo chown -R 845:845 ${FACTORIO_PVC}
kubectl scale deployment -n games factorio-server --replicas=1
```

#### 4. Seed Minecraft World Data (Local-Path NVMe Volume)
```bash
kubectl scale deployment -n games minecraft --replicas=0
# Local-path provisioner creates volumes under /persist/kubernetes/local-storage
MC_PVC=$(ls -d /persist/kubernetes/local-storage/pvc-* 2>/dev/null || ls -d /persist/kubernetes/storage/games-minecraft-data-*)
sudo rsync -avzP /persist/backup/minecraft/ ${MC_PVC}/
# Fix ownership for itzg container user (UID 1000)
sudo chown -R 1000:1000 ${MC_PVC}
kubectl scale deployment -n games minecraft --replicas=1
```

### Step 4.3: Verify All Services (Without DNS Collision)
Test all services locally before modifying public DNS:

```bash
# Verify Joplin:
kubectl port-forward -n productivity svc/joplin 22300:22300
# Open http://localhost:22300 in browser and verify notes/login.

# Verify Zotero WebDAV:
kubectl port-forward -n productivity svc/zotero 8081:80
curl -u unbalance:<password> http://localhost:8081/zotero/

# Verify Factorio:
# Connect game client to: <hydra-ip>:34197

# Verify Minecraft & Voice:
kubectl logs -n games deploy/minecraft -c minecraft-server -f
kubectl logs -n games deploy/minecraft -c playit-agent -f
```

---

## 5. Phase 3: Wipe & Rebuild Venus as Pluto

Once all services are validated on Hydra, Venus can be safely rebuilt into Pluto.

1. SSH into Venus:
   ```bash
   ssh root@venus
   ```
2. Trigger the rebuild using the `pluto` flake configuration from `solar`:
   ```bash
   sudo nixos-rebuild switch --flake "github:Apollo-sudo767/solar#pluto"
   ```
   *(If performing a fresh clean-disk installation, boot the Solar Live USB and run `sudo nix run github:nix-community/disko -- --mode zap-create-mount --flake "github:Apollo-sudo767/solar#pluto"` followed by `sudo nixos-install --flake "github:Apollo-sudo767/solar#pluto"`).*
3. Reboot the machine:
   ```bash
   sudo reboot
   ```

---

## 6. Phase 4: Automatic Compute Join & Pod Scheduling

When Pluto boots up:
1. **Cluster Join**: Pluto reads `k3s-token.age`, connects to `https://hydra:6443`, and joins the high-availability etcd quorum.
2. **Node Labeling**: Pluto receives the label `node.type=compute`.
3. **Pod Scheduling**: Kubernetes and Flux CD detect the high-performance compute node. Game servers configured with compute node affinity (Minecraft, Factorio, TF2) **automatically schedule onto Pluto**.
4. **Transparent LAN Mounts**: Pods running on Pluto immediately mount their persistent volumes from Hydra over NFS across the local network. No data migration is required for Pluto to begin running workloads!

Check cluster status from Hydra:
```bash
kubectl get nodes -o wide
# Verify pluto is Ready with label node.type=compute
kubectl get pods -A -o wide
# Verify game server pods are scheduled on pluto
```

---

## 7. Phase 5: Cut Over Shared NFS Storage from Hydra to Pluto

Now that Pluto is operational with its fast 1TB NVMe drive, shift the cluster NFS storage from Hydra to Pluto.

### Step 7.1: Pause Stateful Workloads
```bash
kubectl scale deployment -n games minecraft factorio-server --replicas=0
kubectl scale deployment -n productivity joplin-server joplin-postgres zotero --replicas=0
```

### Step 7.2: Sync Storage from Hydra to Pluto
Run this command on Hydra to copy all active volumes to Pluto:
```bash
sudo rsync -avzP /persist/kubernetes/storage/ root@pluto:/persist/kubernetes/storage/
```

### Step 7.3: Update GitOps Configuration
In `infrastructure/nfs-provisioner/deployment.yaml`:

```yaml
# Update NFS_SERVER from hydra to pluto:
- name: NFS_SERVER
  value: "pluto"
```

Commit and push:
```bash
cd ~/src/pluto-cluster
git add infrastructure/nfs-provisioner/deployment.yaml
git commit -m "chore(storage): cut over primary NFS storage from hydra to pluto"
git push origin main
```

### Step 7.4: Reconcile & Resume
```bash
flux reconcile kustomization infrastructure --with-source
kubectl scale deployment -n games minecraft factorio-server --replicas=1
kubectl scale deployment -n productivity joplin-server joplin-postgres zotero --replicas=1
```

---

## 8. Phase 6: Production Ingress Cutover & Fleet Cleanup

### Step 8.1: Enable Cloudflare Tunnel
1. In `infrastructure/kustomization.yaml`, uncomment `- cloudflared`.
2. Commit and push.
3. In the Cloudflare Zero Trust dashboard (or DNS management), update the CNAME records for:
   * `joplin.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`
   * `zotero.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`
   * `languagetool.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`

### Step 8.2: Solar Fleet Cleanup
1. In `modules/services/networking/syncthing.nix`, update the introducer node from `venus` to `sol` or your workstation.
2. Remove `modules/hosts/venus/` from `solar`.
3. Rekey secrets: `cd ~/src/solar && s-rekey`.
