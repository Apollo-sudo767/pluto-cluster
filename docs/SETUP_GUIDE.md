# 🪐 Pluto Cluster: Comprehensive Setup & Operations Guide

Welcome to the definitive guide for deploying, bootstrapping, and operating the **Pluto High-Availability K3s Cluster**.

This guide covers the complete deployment lifecycle—from the underlying NixOS flake infrastructure and central ZFS NAS storage to GitOps workload management, Nix-managed secrets, and external ingress for games and media.

---

## 📑 Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites & Hardware Nodes](#2-prerequisites--hardware-nodes)
3. [NixOS & NAS Storage Foundation (Sol)](#3-nixos--nas-storage-foundation-sol)
4. [Secret Management Architecture (Nix & Agenix)](#4-secret-management-architecture-nix--agenix)
5. [Cluster Bootstrapping & Quorum Initialization](#5-cluster-bootstrapping--quorum-initialization)
6. [GitOps Deployment with Flux CD](#6-gitops-deployment-with-flux-cd)
7. [External Access & Friend Connectivity](#7-external-access--friend-connectivity)
   - [Playit.gg Integration for Minecraft](#playitgg-sidecar-integration)
   - [Custom Domain & DNS SRV Records](#custom-domain--dns-srv-records)
   - [Cloudflare Ingress for Web Services](#cloudflare-ingress-for-web-services)
8. [Workloads Reference](#8-workloads-reference)
9. [Day-2 Operations & Maintenance](#9-day-2-operations--maintenance)
10. [Troubleshooting Runbook](#10-troubleshooting-runbook)

---

## 1. Architecture Overview

```
                      ┌─────────────────────────────────────────┐
                      │       Sol (Central ZFS Storage NAS)     │
                      │       NFS: sol.local:/tank/k3s-volumes  │
                      └────────────────────┬────────────────────┘
                                           │ Dynamic NFS PVCs
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
                                             │
                   ┌─────────────────────────┴─────────────────────────┐
                   ▼                                                   ▼
┌───────────────────────────────────────┐   ┌─────────────────────────────────────────┐
│     Minecraft Paper 1.21.1 Pod        │   │    Jellyfin & Home Assistant Pods       │
│ ┌───────────────────┐ ┌─────────────┐ │   │ ┌─────────────────┐ ┌─────────────────┐ │
│ │ minecraft-server  │ │playit-agent │ │   │ │    Jellyfin     │ │ Home Assistant  │ │
│ │ (8GB RAM, 25565)  │ │ (Sidecar)   │ │   │ │ (Intel QuickSync│ │ (Home Automation│ │
│ └─────────▲─────────┘ └──────▲──────┘ │   │ │  Transcoding)   │ │  Port 8123)     │ │
│           └────── Loopback ──┘        │   │ └────────┬────────┘ └────────┬────────┘ │
└───────────────────▲───────────────────┘   └──────────┼───────────────────┼──────────┘
                    │ Outbound Tunnel                  └─────────┬─────────┘
                    ▼                                            ▼
           [ Playit.gg Anycast ]                     [ Cloudflare Tunnel (`cloudflared`) ]
                    ▲                                            ▲
          mc.yourdomain.com                          jellyfin.yourdomain.com
          (SRV Record)                              homeassistant.yourdomain.com
```

---

## 2. Prerequisites & Hardware Nodes

The cluster operates across four dedicated physical machines configured declaratively in the [`solar`](https://github.com/Apollo-sudo767/solar) NixOS flake:

| Node | Hardware Spec | Role | Special System Configurations |
| :--- | :--- | :--- | :--- |
| **`pluto`** | Beelink EQR5 (Ryzen 7 5825U, 32GB RAM, NVMe) | Bootstrap Master (`clusterInit`) | `node.type=compute`, secrets synchronization daemon |
| **`styx`** | Lenovo ThinkPad T14 Gen 2 (i5, 16GB RAM, NVMe) | Control-Plane Master | Battery capped at 50% (`TLP`), lid-switch ignored, disabled WiFi power save |
| **`hydra`** | Lenovo ThinkCentre M920q Tiny (i5-8500T, 16GB RAM) | Control-Plane Master | `gpu.vendor=intel`, Intel QuickSync hardware transcoding pass-through (`/dev/dri`) |
| **`sol`** | Central ZFS Storage Server (Multi-NIC, HDD array) | Fleet NAS & Storage Hub | ZFS pool `tank`, NFS export `/tank/k3s-volumes` with `no_root_squash` |

All compute nodes run **stateless root filesystems** using tmpfs rollback on boot (Preservation/Impermanence) to guarantee reproducible, immutable nodes.

---

## 3. Storage Foundation: Temporary Pluto NFS & Sol NAS Migration

### 3.1 Phase 1 (Current): Temporary NFS on `pluto`
Until your dedicated ZFS NAS (`sol`) is built, **`pluto` acts as the temporary NFS storage host**:
- Pluto exports `/persist/k3s-volumes` with `rw,sync,no_root_squash`.
- Both `styx` and `hydra` mount this share over the network.
- Game servers (Minecraft, Factorio, TF2) and Home Assistant use this shared storage class (`nfs-client`).
- High-storage media workloads (`jellyfin`, `arr` suite) remain disabled in `apps/kustomization.yaml` to prevent filling Pluto's NVMe drive.

Verify Pluto's NFS export:
```bash
showmount -e pluto
# Output will display:
# /persist/k3s-volumes *
```

### 3.2 Phase 2: Migration to `sol` NAS (When Built)
Once `sol` is assembled and running with its ZFS `tank` pool:
1. Copy the game saves and volumes over the network:
   ```bash
   rsync -av /persist/k3s-volumes/ sol:/tank/k3s-volumes/
   ```
2. In `infrastructure/nfs-provisioner/deployment.yaml`, update `NFS_SERVER` to `sol.local` and `NFS_PATH` to `/tank/k3s-volumes`.
3. In `apps/kustomization.yaml`, uncomment `- jellyfin` and `- arr`.
4. Push to GitOps (`git push origin main`), and Flux/K3s will automatically migrate and deploy the full media streaming stack!

---

## 4. Secret Management Architecture (Nix & Agenix)

> [!IMPORTANT]
> **Zero plaintext secrets or secret manifests exist in this GitOps repository.**
> All credentials are encrypted using Age via [`agenix-rekey`](https://github.com/Apollo-sudo767/solar) in your private [`solar-secrets`](https://github.com/Apollo-sudo767/solar-secrets) repository.

### 4.1 Required Secrets Inventory

| Secret | Target Age File in `solar-secrets` | Format / Value |
| :--- | :--- | :--- |
| **K3s Cluster Token** | `secrets/k3s-token.age` | Secure random string: `openssl rand -hex 32` |
| **Playit Agent Secret** | `secrets/playit-secret.age` | Plain secret key string obtained from Playit.gg |
| **Cloudflare Credentials** | `secrets/cloudflared-credentials.age` | Complete credentials JSON from `cloudflared tunnel create` |
| **Surfshark WireGuard** | `secrets/surfshark-vpn.age` | Key-value env file: `WIREGUARD_PRIVATE_KEY` and `WIREGUARD_ADDRESSES` |

### 4.2 Creating Node Public Keys (`hosts/`)
For `agenix-rekey` to encrypt secrets for your cluster machines, extract each machine's Age public key:
```bash
# On each node (or extract from /persist/etc/ssh/ssh_host_ed25519_key.pub):
ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub
```
Save the resulting `age1...` strings into:
- `~/src/solar-secrets/hosts/pluto.pub`
- `~/src/solar-secrets/hosts/styx.pub`
- `~/src/solar-secrets/hosts/hydra.pub`
- `~/src/solar-secrets/hosts/sol.pub`

### 4.3 Editing and Rekeying Secrets
```bash
cd ~/src/solar-secrets

# 1. Create K3s Join Token:
s-edit secrets/k3s-token.age

# 2. Create Playit Secret:
s-edit secrets/playit-secret.age

# 3. Create Cloudflare Tunnel Credentials:
s-edit secrets/cloudflared-credentials.age

# 4. Create Surfshark WireGuard VPN Credentials:
# (Obtain private key and address from my.surfshark.com -> VPN -> Manual -> WireGuard)
s-edit secrets/surfshark-vpn.age
# Content:
# WIREGUARD_PRIVATE_KEY=your_private_key_here
# WIREGUARD_ADDRESSES=10.14.0.2/16

# 5. Rekey secrets for all cluster nodes:
cd ~/src/solar
s-rekey
git add rekeyed/
git commit -m "chore: rekey secrets for pluto cluster"
git push origin main
```

### 4.4 Automated Secret Synchronization Daemon
On `pluto`, NixOS runs `k3s-secrets-sync.service`. On boot, once the K3s API server is ready, it automatically creates:
- `games/playit-secret`: With key `PLAYIT_SECRET_KEY`
- `cloudflared/cloudflared-credentials`: With file `credentials.json`
- `media/surfshark-vpn-secret`: With keys `WIREGUARD_PRIVATE_KEY` and `WIREGUARD_ADDRESSES`

---

## 5. Cluster Bootstrapping & Quorum Initialization

### Step 1: Deploy Node 1 (`pluto` - Bootstrap Master)
Deploy the NixOS configuration to `pluto`. Because `clusterInit = true` is enabled in `modules/hosts/pluto/default.nix`, K3s initializes a new embedded etcd cluster.
```bash
# Verify K3s is active on pluto:
systemctl status k3s

# Check initial node status:
kubectl get nodes -o wide
```

### Step 2: Join Node 2 (`styx`) and Node 3 (`hydra`)
Deploy the NixOS configurations to `styx` and `hydra`. Both are configured with `serverAddr = "https://pluto:6443"` and automatically read the decrypted `k3s-token.age`.

Once the services start, verify the 3-node etcd quorum from `pluto`:
```bash
kubectl get nodes
```
Expected output:
```text
NAME    STATUS   ROLES                       AGE   VERSION
pluto   Ready    control-plane,etcd,master   10m   v1.30.x+k3s1
styx    Ready    control-plane,etcd,master   5m    v1.30.x+k3s1
hydra   Ready    control-plane,etcd,master   2m    v1.30.x+k3s1
```

### Step 3: Verify Node Labels
Workloads are scheduled onto specific nodes using labels:
```bash
kubectl get nodes --show-labels
```
- Verify `pluto` has `node.type=compute` (reserves heavy CPU/RAM for Minecraft Paper).
- Verify `hydra` has `gpu.vendor=intel` (targets Intel QuickSync video transcoding for Jellyfin).

---

## 6. GitOps Deployment with Flux CD

Workloads, storage provisioners, and ingress controllers are managed declaratively by Flux CD from this repository.

### Step 1: Run the Bootstrap Helper
On `pluto` (or any machine with admin `KUBECONFIG` access to the cluster):
```bash
cd ~/src/pluto-cluster
./bootstrap.sh
```

The script will:
1. Validate cluster connectivity via `kubectl`.
2. Check for or install the Flux CLI.
3. Install the Flux controllers into the `flux-system` namespace.
4. Synchronize the Git repository `git@github.com:Apollo-sudo767/pluto-cluster.git`.
5. Apply the root Kustomizations (`clusters/pluto/infrastructure.yaml` and `clusters/pluto/apps.yaml`).

### Step 2: Track GitOps Synchronization Status
```bash
flux get kustomizations
flux get sources git
```

### Step 3: Verify Dynamic Storage Provisioning
The cluster includes `nfs-subdir-external-provisioner` pointing to `sol.local:/tank/k3s-volumes`:
```bash
kubectl get storageclass
```
Expected output:
```text
NAME                   PROVISIONER                               RECLAIMPOLICY   VOLUMEBINDINGMODE
nfs-client (default)   cluster.local/nfs-subdir-external-provisioner   Delete          Immediate
```

---

## 7. External Access & Friend Connectivity

### Playit.gg Sidecar Integration
Minecraft uses Playit.gg to bypass firewalls and CGNAT without port forwarding:
1. The Minecraft deployment runs `itzg/minecraft-server` and `playitgg/playit-agent` within the same pod.
2. The agent reads `PLAYIT_SECRET_KEY` and establishes an outbound tunnel to Playit.gg's network.
3. Incoming game packets are delivered over the tunnel to `localhost:25565`.

#### Custom Domain & DNS SRV Records
To let friends connect using your domain (e.g. `mc.yourdomain.com`) without typing ports:

1. In the [Playit Dashboard](https://playit.gg):
   - Open your agent tunnel ➔ Select **Custom Domains** ➔ Add `mc.yourdomain.com`.
   - Note the assigned tunnel target (e.g. `galaxy-1234.craft.playit.gg`) and port (e.g. `34215`).

2. In your DNS Provider (e.g., **Cloudflare DNS**):
   - Add a **CNAME** Record:
     - **Name**: `mc`
     - **Target**: `galaxy-1234.craft.playit.gg`
     - **Proxy status**: **DNS Only (Grey Cloud)**
   - Add an **SRV** Record (routes Minecraft traffic directly to the right port):
     - **Service**: `_minecraft`
     - **Protocol**: `TCP`
     - **Name**: `mc`
     - **Priority**: `0`
     - **Weight**: `5`
     - **Port**: `34215` (Your assigned Playit port)
     - **Target**: `mc.yourdomain.com`

Friends can now join the server by entering `mc.yourdomain.com` in their Minecraft client!

---

### Cloudflare Ingress for Web Services
Web services (Jellyfin and Home Assistant) are exposed securely over HTTPS via Cloudflare Tunnels:

1. Edit [`infrastructure/cloudflared/configmap.yaml`](../infrastructure/cloudflared/configmap.yaml):
   ```yaml
   ingress:
     - hostname: jellyfin.yourdomain.com
       service: http://jellyfin.media.svc.cluster.local:8096
     - hostname: homeassistant.yourdomain.com
       service: http://home-assistant.home-automation.svc.cluster.local:8123
     - service: http_status:404
   ```
2. In Cloudflare DNS, add CNAME records for each hostname pointing to `<tunnel-id>.cfargotunnel.com` (Proxied / Orange Cloud).

---

## 8. Workloads Reference

| Workload | Namespace | Node Target | Memory / CPU | Storage PVC | Features |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Paper Minecraft** | `games` | `pluto` (`node.type=compute`) | 8Gi RAM / 4 vCPU | 50Gi (`nfs-client`) | Paper 1.21.1, Aikar JVM flags, Playit sidecar |
| **Jellyfin** | `media` | `hydra` (`gpu.vendor=intel`) | 4Gi RAM / 2 vCPU | 20Gi Config + Sol Media NFS | Intel QuickSync hardware transcoding (`/dev/dri`) |
| **Home Assistant** | `home-automation` | Any | 1Gi RAM / 1 vCPU | 10Gi (`nfs-client`) | Host networking, automated device discovery |
| **qBittorrent + VPN** | `media` | Any | 4Gi RAM / 2 vCPU | 10Gi Config + Sol Media NFS | **Gluetun Surfshark WireGuard VPN** sidecar, automatic kill switch |
| **Sonarr** | `media` | Any | 1Gi RAM / 1 vCPU | 5Gi Config + Sol Media NFS | Automated TV series management, torrent integration |
| **Radarr** | `media` | Any | 1Gi RAM / 1 vCPU | 5Gi Config + Sol Media NFS | Automated movie collection management, torrent integration |
| **Prowlarr** | `media` | Any | 512Mi RAM / 0.5 vCPU | 5Gi Config | Centralized torrent/Usenet indexer manager |

---

## 9. Day-2 Operations & Maintenance

### Staggered Maintenance & Automated Reboots
To keep the cluster continuously updated without dropping etcd quorum, each node runs automated NixOS upgrades and reboots on Sunday morning, staggered by 30 minutes:

| Node | Reboot Schedule | Quorum Status During Window |
| :--- | :--- | :--- |
| **`pluto`** | Sunday 03:00 UTC | 2/3 masters online (`styx`, `hydra`) — Quorum preserved |
| **`styx`** | Sunday 03:30 UTC | 2/3 masters online (`pluto`, `hydra`) — Quorum preserved |
| **`hydra`** | Sunday 04:00 UTC | 2/3 masters online (`pluto`, `styx`) — Quorum preserved |

### Deploying Workload Updates
To update application images, environment variables, or resource allocations:
1. Edit manifests in `apps/` or `infrastructure/` in this repository.
2. Commit and push:
   ```bash
   git commit -am "feat: update minecraft to version 1.21.2"
   git push origin main
   ```
3. Flux CD detects the commit and applies changes within 1 minute (or force immediate sync via `flux reconcile kustomization apps --with-source`).

---

## 10. Troubleshooting Runbook

### Issue 1: Pods Stuck in `Pending` with Storage Errors
- **Check**: `kubectl describe pvc -n <namespace>`
- **Resolution**: Verify Sol NFS export is reachable from all nodes:
  ```bash
  rpcinfo -p sol.local
  showmount -e sol.local
  ```
  Ensure `nfs-subdir-external-provisioner` pod is running in `nfs-provisioner` namespace.

### Issue 2: Node Fails to Join K3s Quorum
- **Check**: `journalctl -u k3s -e` on the failing node.
- **Resolution**: Check if the token matches. Verify the token file on the node:
  ```bash
  cat /run/agenix/k3s-token.age
  ```
  Ensure TCP ports `6443` (Kubernetes API) and `2379:2380` (etcd) are accessible over the internal network.

### Issue 3: Friends Cannot Connect to Minecraft
- **Check**: View the Playit sidecar logs:
  ```bash
  kubectl logs -n games -l app=minecraft -c playit-agent
  ```
- **Resolution**:
  - If log says `Invalid secret key`: Check `solar-secrets/secrets/playit-secret.age` and verify the secret was properly applied.
  - If log says `Connected`: Verify that your DNS SRV record port matches the port shown in your Playit tunnel dashboard.
