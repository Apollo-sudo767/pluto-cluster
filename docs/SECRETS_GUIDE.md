# 🔐 Pluto Cluster: Secrets Provisioning & Encryption Guide

This guide provides step-by-step instructions for obtaining, creating, and encrypting all secrets required by the **Pluto Cluster** and its workloads.

> [!IMPORTANT]
> **Zero plaintext secrets or secret manifests are stored in the `pluto-cluster` repository.**
> All credentials are encrypted with Age using [`agenix-rekey`](https://github.com/oddlama/agenix-rekey) in your private [`solar-secrets`](https://github.com/Apollo-sudo767/solar-secrets) repository, and synced automatically into Kubernetes namespaces on boot by NixOS via `k3s-secrets-sync.service`.

---

## 📑 Table of Contents
1. [Required Secrets Overview](#1-required-secrets-overview)
2. [Secret 1: K3s Cluster Token (`k3s-token.age`)](#2-secret-1-k3s-cluster-token-k3s-tokenage)
3. [Secret 2: Playit.gg Secret Key (`playit-secret.age`)](#3-secret-2-playitgg-secret-key-playit-secretage)
4. [Secret 3: Surfshark WireGuard VPN (`surfshark-vpn.age`)](#4-secret-3-surfshark-wireguard-vpn-surfshark-vpnage)
5. [Secret 4: Cloudflare Tunnel Credentials (`cloudflared-credentials.age`)](#5-secret-4-cloudflare-tunnel-credentials-cloudflared-credentialsage)
6. [Machine Public Keys (`hosts/<hostname>.pub`)](#6-machine-public-keys-hostshostnamepub)
7. [Rekeying & Deploying All Secrets](#7-rekeying--deploying-all-secrets)
8. [How to Decrypt and Verify Secrets](#8-how-to-decrypt-and-verify-secrets)

---

## 1. Required Secrets Overview

| Secret File in `solar-secrets` | Target Kubernetes Secret | Namespace | Consuming Workload |
| :--- | :--- | :--- | :--- |
| `secrets/k3s-token.age` | Node join token (NixOS level) | N/A | `pluto`, `styx`, `hydra` (Control Plane) |
| `secrets/playit-secret.age` | `playit-secret` | `games` | Paper Minecraft (`playit-agent` sidecar) |
| `secrets/surfshark-vpn.age` | `surfshark-vpn-secret` | `media` | `qbittorrent` (`gluetun` VPN sidecar) |
| `secrets/cloudflared-credentials.age` | `cloudflared-credentials` | `cloudflared` | Cloudflare Ingress Tunnel (`cloudflared`) |

---

## 2. Secret 1: K3s Cluster Token (`k3s-token.age`)

Used by Pluto, Styx, and Hydra to authenticate and join the high-availability etcd control plane.

- **Where to get it**: Nowhere external! You generate it yourself on your own machine.
- **How to get it**: Generate a secure 32-byte random hex string.
- **Command to encrypt**:
  ```bash
  openssl rand -hex 32 | nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age \
    -R ~/src/solar-secrets/master/apollo_user.pub \
    -R ~/src/solar-secrets/master/yubikey.pub \
    -o ~/src/solar-secrets/secrets/k3s-token.age
  ```

---

## 3. Secret 2: Playit.gg Secret Key (`playit-secret.age`)

Used by the Minecraft pod sidecar so friends can connect to your server without port forwarding.

- **Where to get it**: [playit.gg](https://playit.gg)
- **How to get it**:
  1. Log into your account at [playit.gg](https://playit.gg).
  2. In the left sidebar, click **Agents** ➔ **Add Agent**.
  3. Under that agent's settings, copy the **Agent Secret Key** (a long alphanumeric string).
  4. Click **Add Tunnel** ➔ Type: **Minecraft Java** ➔ Port: `25565`.
- **Command to encrypt**:
  ```bash
  # 1. Write the key to a temporary file:
  echo -n "PASTE_YOUR_PLAYIT_SECRET_KEY_HERE" > /tmp/playit.secret

  # 2. Encrypt it:
  nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age \
    -R ~/src/solar-secrets/master/apollo_user.pub \
    -R ~/src/solar-secrets/master/yubikey.pub \
    -o ~/src/solar-secrets/secrets/playit-secret.age \
    /tmp/playit.secret

  # 3. Clean up the plaintext file:
  rm -f /tmp/playit.secret
  ```

---

## 4. Secret 3: Surfshark WireGuard VPN (`surfshark-vpn.age`)

Used by Gluetun to route 100% of torrent traffic from qBittorrent through an encrypted VPN tunnel with an automatic kill switch.

- **Where to get it**: [my.surfshark.com](https://my.surfshark.com)
- **How to get it**:
  1. Log into [my.surfshark.com](https://my.surfshark.com).
  2. Navigate to **VPN** ➔ **Manual setup** ➔ **WireGuard**.
  3. Select or generate a key pair. You will receive:
     - **Private key** (e.g. `cGFzc3dvcm...=`)
     - **IP Address** (e.g. `10.14.0.2/16`)
- **Command to encrypt**:
  ```bash
  # 1. Create a temporary file with the credentials:
  cat << 'EOF' > /tmp/surfshark.env
  WIREGUARD_PRIVATE_KEY=PASTE_YOUR_PRIVATE_KEY_HERE
  WIREGUARD_ADDRESSES=10.14.0.2/16
  EOF

  # 2. Encrypt it:
  nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age \
    -R ~/src/solar-secrets/master/apollo_user.pub \
    -R ~/src/solar-secrets/master/yubikey.pub \
    -o ~/src/solar-secrets/secrets/surfshark-vpn.age \
    /tmp/surfshark.env

  # 3. Clean up the plaintext file:
  rm -f /tmp/surfshark.env
  ```

---

## 5. Secret 4: Cloudflare Tunnel Credentials (`cloudflared-credentials.age`)

Used by Cloudflare to route secure inbound HTTPS traffic to Jellyfin and Home Assistant.

- **Where to get it**: Cloudflare Zero Trust Dashboard or the Cloudflare CLI.
- **How to get it**:
  1. Log into Cloudflare with the CLI:
     ```bash
     nix shell nixpkgs#cloudflared -c cloudflared tunnel login
     ```
  2. Create the tunnel:
     ```bash
     nix shell nixpkgs#cloudflared -c cloudflared tunnel create pluto-cluster
     ```
     This generates a credentials JSON file at `~/.cloudflared/<TUNNEL_ID>.json`.
- **Command to encrypt**:
  ```bash
  nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age \
    -R ~/src/solar-secrets/master/apollo_user.pub \
    -R ~/src/solar-secrets/master/yubikey.pub \
    -o ~/src/solar-secrets/secrets/cloudflared-credentials.age \
    ~/.cloudflared/<TUNNEL_ID>.json
  ```

---

## 6. Machine Public Keys (`hosts/<hostname>.pub`)

`agenix-rekey` needs to know each physical machine's Age public key so it can encrypt/rekey secrets specifically for them.

- **Where to get them**: Directly from each machine (`pluto`, `styx`, `hydra`, `sol`).
- **How to get them**:
  Run this command on each machine (or remotely via SSH):
  ```bash
  cat /persist/etc/ssh/ssh_host_ed25519_key.pub | nix shell nixpkgs#ssh-to-age -c ssh-to-age
  ```
  *(If the machine has not enabled `/persist` yet, use `/etc/ssh/ssh_host_ed25519_key.pub`)*.
- **Where to save them**:
  Save the resulting `age1...` string directly into a text file in `solar-secrets/hosts/` (these are public keys, so no encryption needed):
  - `~/src/solar-secrets/hosts/pluto.pub`
  - `~/src/solar-secrets/hosts/styx.pub`
  - `~/src/solar-secrets/hosts/hydra.pub`
  - `~/src/solar-secrets/hosts/sol.pub`

---

## 7. Rekeying & Deploying All Secrets

Once your secret files exist in `~/src/solar-secrets/secrets/`:

```bash
# 1. Commit in solar-secrets:
cd ~/src/solar-secrets
git add secrets/ hosts/
git commit -m "feat(secrets): add cluster secrets and node pubkeys"

# 2. Rekey in solar:
cd ~/src/solar
s-rekey
# (Touch your YubiKey when it flashes)

# 3. Commit and push the rekeyed secrets:
git add rekeyed/
git commit -m "chore(secrets): rekey all secrets for pluto cluster"
git push origin main
```

---

## 8. How to Decrypt and Verify Secrets

To verify that your secrets are correctly encrypted and readable by your master keys:

### Decrypt using your YubiKey:
```bash
nix shell nixpkgs#age nixpkgs#age-plugin-yubikey -c age \
  -d \
  ~/src/solar-secrets/secrets/<secret-name>.age
```
*(Enter your YubiKey PIN and touch when prompted)*.

### Decrypt using your SSH private key:
```bash
nix shell nixpkgs#age -c age \
  -d \
  -i ~/.ssh/id_ed25519 \
  ~/src/solar-secrets/secrets/<secret-name>.age
```

### View/Edit using the built-in alias (after `s-rekey` has run):
```bash
cd ~/src/solar
s-edit
```
*(Presents an interactive `fzf` menu to decrypt and edit with your master identity)*.
