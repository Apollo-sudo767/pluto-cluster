# 🪐 Pluto Cluster: Venus ➔ MacBook ➔ ThinkCentre (Hydra) ➔ Pluto Complete Migration & Deployment Runbook

This document is the master operational runbook for migrating all stateful workloads, game servers, databases, and persistent volumes from the standalone bare-metal NixOS server **`venus`** to the **Pluto High-Availability K3s Cluster**.

This revised procedure uses your **MacBook laptop as the safe harbor stash and deployment conduit**, tests all workloads in live pods on **`hydra` (Lenovo ThinkCentre M920q)**, stages Pluto's SSH host key via the MacBook, provisions **`pluto` (Beelink EQR5)** cleanly with Disko LUKS + Btrfs, and cuts over primary storage to Pluto.

---

## 📑 Table of Contents

1. [Architectural Overview & The Laptop-First Migration Strategy](#1-architectural-overview--the-laptop-first-migration-strategy)
2. [Hardware Fleet & Resource Allocation](#2-hardware-fleet--resource-allocation)
3. [Phase 1: Backup & Stash Venus State onto MacBook (Laptop)](#3-phase-1-backup--stash-venus-state-onto-macbook-laptop)
4. [Phase 2: Transfer Staged Data from MacBook to ThinkCentre (`hydra`)](#4-phase-2-transfer-staged-data-from-macbook-to-thinkcentre-hydra)
5. [Phase 3: Seed Persistent Volumes & Test Workloads on Hydra (Zero Risk)](#5-phase-3-seed-persistent-volumes--test-workloads-on-hydra-zero-risk)
6. [Phase 4: Stage Pluto SSH Host Key & Clean Install Pluto via Solar Installer](#6-phase-4-stage-pluto-ssh-host-key--clean-install-pluto-via-solar-installer)
   - [Step 4.1: Transfer Pluto SSH Host Key from Mars to MacBook](#step-41-transfer-pluto-ssh-host-key-from-mars-to-macbook)
   - [Step 4.2: Boot Pluto Hardware with Solar Live Installer USB](#step-42-boot-pluto-hardware-with-solar-live-installer-usb)
   - [Step 4.3: Transfer Pluto SSH Key from MacBook to Pluto Installer](#step-43-transfer-pluto-ssh-key-from-macbook-to-pluto-installer)
   - [Step 4.4: Execute `solar-install` & Partition NVMe with Disko](#step-44-execute-solar-install--partition-nvme-with-disko)
7. [Phase 5: Automatic Compute Join & 3-Node HA Quorum](#7-phase-5-automatic-compute-join--3-node-ha-quorum)
8. [Phase 6: Transfer Workload Data to Pluto & Cut Over Primary Storage](#8-phase-6-transfer-workload-data-to-pluto--cut-over-primary-storage)
9. [Phase 7: Production Ingress Cutover & Fleet Cleanup](#9-phase-7-production-ingress-cutover--fleet-cleanup)

---

## 1. Architectural Overview & The Laptop-First Migration Strategy

### Why Stash on the MacBook First?

**`venus` and `pluto` share the exact same physical hardware** (a Beelink EQR5 mini PC with Ryzen 7 5825U and 32GB RAM). Turning Venus into Pluto requires a destructive disk wipe to partition the NVMe with Disko LUKS encryption, Btrfs subvolumes, and ephemeral tmpfs impermanence.

Because the physical machine must be wiped:
1. **Isolated Safe Harbor**: Backing up to your MacBook laptop guarantees an independent offline copy of all databases, WebDAV attachments, game saves, and modpacks before any server is modified or formatted.
2. **Mobile Deployment Transit**: Your MacBook acts as the on-site operator console. It can connect directly over LAN or Tailscale to Venus, Hydra, and the live Pluto installer.
3. **SSH Host Key Staging**: The persistent SSH host key for Pluto (`ssh_host_ed25519_key`) is stored on `mars` (`~/.ssh/hosts/pluto/`). By copying it to your MacBook first, you can easily push it over SCP into the Pluto installer environment during the clean install.

```
┌────────────────────────┐
│  Venus (Bare-Metal)    │
│  Standalone Server     │
└───────────┬────────────┘
            │ 1. Backup DBs, WebDAV, Factorio, Minecraft
            ▼
┌────────────────────────┐
│  MacBook (Laptop)      │ ◄── [ Mars ] (Provides ~/.ssh/hosts/pluto key)
│  Safe Harbor Stash     │
└───────────┬────────────┘
            │ 2. Push backup data
            ▼
┌────────────────────────┐
│  Hydra (ThinkCentre)   │
│  24GB RAM Master       │ 3. Seed PVCs & verify all pods running via Flux
└───────────┬────────────┘
            │ 4. Boot Solar Live USB on Beelink
            │ 5. SCP Pluto SSH host key from MacBook to installer
            │ 6. Run solar-install (Disko LUKS + NixOS)
            ▼
┌────────────────────────┐
│  Pluto (Installed)     │ 7. Joins K3s (node.type=compute) -> 3-Node HA Quorum
│  1TB NVMe Compute Master│ 8. Cut over NFS storage from Hydra to Pluto
└────────────────────────┘
```

---

## 2. Hardware Fleet & Resource Allocation

With **Hydra equipped with 24GB RAM**, memory constraints are eliminated during staging. All workloads can run simultaneously on Hydra for testing:

| Node | Physical Hardware | Specs & Roles | Memory | Staging Role |
| :--- | :--- | :--- | :--- | :--- |
| **`hydra`** | Lenovo ThinkCentre M920q Tiny | Intel i5-8500T (6C/6T), NVMe | **24GB RAM** | K3s Bootstrap Master (`clusterInit`), Phase 1 NFS Server |
| **`styx`** | Lenovo ThinkPad T14 Gen 2 | Intel Core i5, NVMe, Battery UPS | **16GB RAM** | K3s Control-Plane Master (joins `hydra`) |
| **`pluto`** *(formerly Venus)* | Beelink EQR5 | AMD Ryzen 7 5825U (8C/16T), 1TB NVMe | **32GB RAM** | Final Compute Master (`node.type=compute`), Phase 2 NFS Server |

### Hydra Memory Budget (Full Pod Verification)
* K3s Control Plane & Host OS: `~1.5 GB`
* Joplin Server & PostgreSQL: `~1.5 GB`
* Zotero WebDAV & Nginx Proxy: `~0.2 GB`
* LanguageTool API: `~1.5 GB`
* Factorio Headless Server: `~2.5 GB`
* Minecraft Server (PhasMC 1.21.1 NeoForge modpack): `~12.0 GB`
* **Total Committed**: `~19.0 GB` (Leaves `~5.0 GB` safe buffer on Hydra)

---

## 3. Phase 1: Backup & Stash Venus State onto MacBook (Laptop)

Before touching Venus, create a dedicated backup directory on your MacBook and copy all persistent application data over SSH/rsync.

### Step 3.1: Prepare Staging Directory on MacBook
On your MacBook terminal:
```bash
mkdir -p ~/backup/{joplin,zotero,factorio,minecraft}
```

### Step 3.2: Backup Joplin PostgreSQL Database
On `venus`, stop Joplin to ensure transaction consistency, generate an SQL dump, and pull it to your MacBook:
```bash
# 1. Stop Joplin server on Venus
ssh root@venus "systemctl stop joplin-server"

# 2. Dump PostgreSQL database cleanly
ssh root@venus "sudo -u postgres pg_dump -d joplin --clean --if-exists > /tmp/joplin_backup.sql"

# 3. Pull dump to MacBook
scp root@venus:/tmp/joplin_backup.sql ~/backup/joplin/
```

### Step 3.3: Backup Zotero WebDAV Attachments
Pull all Zotero sync files to the MacBook:
```bash
rsync -avzP root@venus:/var/lib/zotero-webdav/zotero/ ~/backup/zotero/
```

### Step 3.4: Backup Factorio Saves & Configurations
```bash
# 1. Stop Factorio service
ssh root@venus "systemctl stop factorio"

# 2. Pull saves, mods, and server config to MacBook
rsync -avzP root@venus:/var/lib/factorio/saves/ ~/backup/factorio/saves/

if ssh root@venus "[ -d /var/lib/factorio/mods ]"; then
  rsync -avzP root@venus:/var/lib/factorio/mods/ ~/backup/factorio/mods/
fi

if ssh root@venus "[ -f /var/lib/factorio/config/server-settings.json ]"; then
  rsync -avzP root@venus:/var/lib/factorio/config/server-settings.json ~/backup/factorio/server-settings.json
fi
```

### Step 3.5: Backup Minecraft Modpack Server (Dereferencing Nix Store)
> [!IMPORTANT]
> In `nix-minecraft`, mods and configs are symlinks pointing into `/nix/store/...`. You **must** pass the **`-L`** flag (`--copy-links`) to `rsync` so real files are copied to your MacBook instead of broken symlinks!

```bash
# 1. Stop Minecraft service
ssh root@venus "systemctl stop minecraft-server-no-mans-land"

# 2. Pull modpack files with dereferenced links
rsync -avzLP root@venus:/srv/minecraft/no-mans-land/ ~/backup/minecraft/
```

---

## 4. Phase 2: Transfer Staged Data from MacBook to ThinkCentre (`hydra`)

Now that your data is safely archived on your laptop, push it over the local network to Hydra's temporary staging directory.

### Step 4.1: Prepare Staging Directory on Hydra
From your MacBook:
```bash
ssh apollo@hydra "sudo mkdir -p /persist/backup/{joplin,zotero,factorio,minecraft} && sudo chown -R apollo:users /persist/backup"
```

### Step 4.2: Sync Data from MacBook to Hydra
```bash
rsync -avzP ~/backup/ apollo@hydra:/persist/backup/
```

Verify that all files arrived on Hydra:
```bash
ssh apollo@hydra "ls -lh /persist/backup/*"
```

---

## 5. Phase 3: Seed Persistent Volumes & Test Workloads on Hydra (Zero Risk)

Hydra's NFS provisioner manages dynamic PVC directories under `/persist/kubernetes/storage/`.

### Step 5.1: Deploy Manifests via Flux CD
Ensure `apps/kustomization.yaml` has your workloads enabled:
```bash
cd ~/src/pluto-cluster
git add apps/ infrastructure/
git commit -m "feat(apps): enable joplin, zotero, factorio, and minecraft"
git push origin main

# Reconcile on Hydra:
ssh apollo@hydra "flux reconcile kustomization apps --with-source"
```

Wait for the PVCs to bind:
```bash
ssh apollo@hydra "kubectl get pvc -A"
```

### Step 5.2: Seed Data into the Bound PVCs

#### 1. Restore Joplin Database
```bash
# Wait for postgres pod
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
kubectl wait --for=condition=ready pod -l app=zotero -n productivity --timeout=120s
ZOTERO_POD=$(kubectl get pod -n productivity -l app=zotero -o jsonpath='{.items[0].metadata.name}')

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
sudo chown -R 845:845 ${FACTORIO_PVC}
kubectl scale deployment -n games factorio-server --replicas=1
```

#### 4. Seed Minecraft World Data (NVMe Storage)
```bash
kubectl scale deployment -n games minecraft --replicas=0
MC_PVC=$(ls -d /persist/kubernetes/local-storage/pvc-* 2>/dev/null || ls -d /persist/kubernetes/storage/games-minecraft-data-*)
sudo rsync -avzP /persist/backup/minecraft/ ${MC_PVC}/
sudo chown -R 1000:1000 ${MC_PVC}
kubectl scale deployment -n games minecraft --replicas=1
```

### Step 5.3: Verify All Services in Pods
Verify services locally before proceeding with hardware modifications:
```bash
# Verify Joplin:
kubectl port-forward -n productivity svc/joplin 22300:22300
# Open http://localhost:22300 in browser.

# Verify Zotero WebDAV:
kubectl port-forward -n productivity svc/zotero 8081:80
curl -u unbalance:<password> http://localhost:8081/zotero/

# Verify Factorio:
# Connect game client to <hydra-ip>:34197

# Verify Minecraft & Voice sidecar:
kubectl logs -n games deploy/minecraft -c minecraft-server -f
kubectl logs -n games deploy/minecraft -c playit-agent -f
```

---

## 6. Phase 4: Stage Pluto SSH Host Key & Clean Install Pluto via Solar Installer

Now that all data is safe on the MacBook and verified live in pods on Hydra, Venus can be cleanly wiped and installed as **Pluto**.

### Step 4.1: Transfer Pluto SSH Host Key from Mars to MacBook

The persistent host key for Pluto is located on `mars` at `~/.ssh/hosts/pluto/`.

**Option A — Push from Mars to MacBook:**
```bash
# On Mars:
scp -r ~/.ssh/hosts/pluto apollo@macbook-pro:~/.ssh/hosts/
```

**Option B — Pull from MacBook (via Tailscale or LAN):**
```bash
# On MacBook:
mkdir -p ~/.ssh/hosts/pluto
scp -r apollo@mars:~/.ssh/hosts/pluto/ ~/.ssh/hosts/pluto/
```

Verify the key files on your MacBook:
```bash
ls -la ~/.ssh/hosts/pluto/
# Outputs: ssh_host_ed25519_key  ssh_host_ed25519_key.pub
```

### Step 4.2: Boot Pluto Hardware with Solar Live Installer USB

1. Insert the Solar Live Installer USB into the Beelink EQR5 (`venus`).
2. Power on and enter the boot menu (F7 or Delete) to boot the Live USB.
3. Ensure the installer machine is connected to Ethernet / Wi-Fi and obtain its IP:
   ```bash
   ip -4 addr show scope global
   ```
   *(Let this address be `<pluto-installer-ip>`)*.

### Step 4.3: Transfer Pluto SSH Key from MacBook to Pluto Installer

From your MacBook terminal, copy the staged host key directly to the live installer:

```bash
# If Disko has already mounted storage:
scp ~/.ssh/hosts/pluto/ssh_host_ed25519_key* root@<pluto-installer-ip>:/mnt/persist/etc/ssh/

# Or stage in /home/nixos/ before running solar-install:
scp ~/.ssh/hosts/pluto/ssh_host_ed25519_key* nixos@<pluto-installer-ip>:/home/nixos/
```

### Step 4.4: Execute `solar-install` & Partition NVMe with Disko

On the Pluto machine (via console or `ssh nixos@<pluto-installer-ip>`):

```bash
sudo solar-install
```

1. **Flake Source**: Select `1` (Pull latest from GitHub).
2. **Host Selection**: Select `pluto`.
3. **Hardware Config**: Select `y` to refresh hardware config for the Ryzen 5825U.
4. **User Password**: Set your administrative account password.
5. **Secrets Mode**: Select `1` (Offline evaluation / locks secrets into flake).
6. **Disko Partitioning**: Type `yes` to confirm wiping the NVMe drive and formatting LUKS + Btrfs.
7. **SSH Host Key Provisioning**: The installer automatically detects the key staged from your MacBook in `/mnt/persist/etc/ssh/` or `/home/nixos/`!
8. **NixOS Install**: The installer runs `nixos-install`, initializes `/etc/shadow`, and copies the Limine EFI bootloader.
9. **Reboot**: Select `y` to reboot into your newly provisioned Pluto node!

---

## 7. Phase 5: Automatic Compute Join & 3-Node HA Quorum

When Pluto boots up:
1. **Host Identity & Secrets**: NixOS mounts `/persist/etc/ssh/ssh_host_ed25519_key` and Agenix seamlessly decrypts `k3s-token.age` and `wifi.age`.
2. **Cluster Join**: Pluto automatically connects to `https://hydra:6443` using the decrypted cluster token and joins the embedded etcd quorum.
3. **Node Labeling**: Pluto is tagged with `node.type=compute`.
4. **3-Node HA Quorum Established**:

Verify the cluster status from Hydra:
```bash
kubectl get nodes -o wide
```
Output will confirm:
* `hydra` (Ready, Control-Plane)
* `styx` (Ready, Control-Plane)
* `pluto` (Ready, Control-Plane, `node.type=compute`)

Game servers with compute affinity will automatically begin scheduling onto Pluto!

---

## 8. Phase 6: Transfer Workload Data to Pluto & Cut Over Primary Storage

Now that Pluto is operational with its fast 1TB NVMe drive and Ryzen 7 CPU, shift the cluster NFS storage from Hydra to Pluto.

### Step 8.1: Pause Stateful Workloads
```bash
kubectl scale deployment -n games minecraft factorio-server --replicas=0
kubectl scale deployment -n productivity joplin-server joplin-postgres zotero --replicas=0
```

### Step 8.2: Sync Storage from Hydra to Pluto
Run this command on Hydra to copy all active volumes to Pluto:
```bash
sudo rsync -avzP /persist/kubernetes/storage/ root@pluto:/persist/kubernetes/storage/
```

If Minecraft is using local-path NVMe on Pluto (`/persist/kubernetes/local-storage`):
```bash
# Push directly from Hydra or MacBook:
sudo rsync -avzP /persist/backup/minecraft/ root@pluto:/persist/kubernetes/local-storage/
```

### Step 8.3: Update GitOps Configuration
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

### Step 8.4: Reconcile & Resume
```bash
flux reconcile kustomization infrastructure --with-source
kubectl scale deployment -n games minecraft factorio-server --replicas=1
kubectl scale deployment -n productivity joplin-server joplin-postgres zotero --replicas=1
```

---

## 9. Phase 7: Production Ingress Cutover & Fleet Cleanup

### Step 9.1: Enable Cloudflare Tunnel
1. In `infrastructure/kustomization.yaml`, uncomment `- cloudflared`.
2. Commit and push:
   ```bash
   git add infrastructure/kustomization.yaml
   git commit -m "feat(ingress): enable cloudflare tunnel"
   git push origin main
   ```
3. In the Cloudflare Zero Trust dashboard, update CNAME records for:
   * `joplin.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`
   * `zotero.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`
   * `languagetool.apollan.cc` ➔ `<TUNNEL_ID>.cfargotunnel.com`

### Step 9.2: Solar Fleet Cleanup
1. In `modules/services/networking/syncthing.nix`, update any legacy references from `venus` to `sol` or your workstation.
2. Remove `modules/hosts/venus/` from the `solar` flake.
3. On Mars, run `s-rekey`, then commit and push.
