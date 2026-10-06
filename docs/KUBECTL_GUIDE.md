# 🧭 Pluto Cluster: The Complete `kubectl` & Operations Guide

A comprehensive, beginner-to-advanced operational guide for mastering `kubectl`, understanding Kubernetes architecture, diagnosing cluster workloads, and managing the **Pluto Cluster** fleet (`hydra`, `styx`, `pluto`).

---

## 📑 Table of Contents

1. [The Mental Model: How Kubernetes & `kubectl` Work](#1-the-mental-model-how-kubernetes--kubectl-work)
2. [Setting Up Cluster Access (Mac Workstation & NixOS)](#2-setting-up-cluster-access-mac-workstation--nixos)
3. [The `kubectl` Grammar (How to Speak Kubernetes)](#3-the-kubectl-grammar-how-to-speak-kubernetes)
4. [Inspecting & Observing (The Read Operations)](#4-inspecting--observing-the-read-operations)
5. [Debugging & Troubleshooting Runbook](#5-debugging--troubleshooting-runbook)
6. [Interactive Operations (`exec`, `logs`, `port-forward`)](#6-interactive-operations-exec-logs-port-forward)
7. [Pluto Fleet Node Scheduling & Placement](#7-pluto-fleet-node-scheduling--placement)
8. [The Ecosystem: `kubectl` vs Helm vs Headlamp vs Flux CD](#8-the-ecosystem-kubectl-vs-helm-vs-headlamp-vs-flux-cd)
9. [Pluto Cluster Quick Reference Cheat Sheet](#9-pluto-cluster-quick-reference-cheat-sheet)

---

## 1. The Mental Model: How Kubernetes & `kubectl` Work

To master `kubectl`, you only need to understand one core concept:

> **The entire Kubernetes cluster is just an HTTP REST API server backed by a key-value database (`etcd`).**

```
 ┌───────────────────────┐
 │ Your Mac / SSH Shell  │
 └──────────┬────────────┘
            │  HTTPS JSON/Protobuf requests
            │  (via ~/.kube/config authentication)
            ▼
 ┌───────────────────────────────────────────────┐
 │       kube-apiserver (Port 6443)              │
 │       Runs on Hydra, Styx, and Pluto          │
 └───────┬───────────────────────────────┬───────┘
         │ Reads/Writes                  │ Reconciles
         ▼                               ▼
 ┌───────────────┐             ┌───────────────────┐
 │  etcd Quorum  │             │   Node Kubelets   │
 │ (Cluster DB)  │             │ (Runs Containers) │
 └───────────────┘             └───────────────────┘
```

1. **`kubectl` is an HTTP client**: Whenever you type `kubectl get pods`, `kubectl` makes an authenticated HTTPS GET request to `https://<api-server>:6443/api/v1/namespaces/.../pods`.
2. **Desired State vs. Actual State**:
   - You declare what you *want* (e.g., "Deploy 1 replica of Headlamp").
   - K3s stores that in `etcd`.
   - The Kubernetes Controllers continuously work to make reality match your declared desire. If a container crashes, the controller starts a new one.
3. **Namespaces are folders**: Resources live inside Namespaces (e.g., `default`, `kube-system`, `headlamp`, `games`, `home-automation`). If you run `kubectl get pods` without specifying a namespace, it only searches `default`.

---

## 2. Setting Up Cluster Access (Mac Workstation & NixOS)

### The Common Pitfall: Why `kubectl` Fails With `connection refused` or `permission denied`

On NixOS / K3s, the cluster configuration lives at `/etc/rancher/k3s/k3s.yaml` and is owned exclusively by `root` (mode `0600`).
- If you run `kubectl get nodes` as a standard user without root privileges, `kubectl` cannot read `/etc/rancher/k3s/k3s.yaml`.
- It falls back to default fallback settings: `http://localhost:8080`, which is closed, resulting in:
  ```text
  The connection to the server localhost:8080 was refused - did you specify the right host or port?
  ```

### Option A: Running on the Nodes (NixOS Shell)
Whenever running directly on `hydra`, `styx`, or `pluto`:
```bash
# Use sudo with kubectl
sudo kubectl get nodes -o wide

# Or use the K3s wrapper
sudo k3s kubectl get pods -A
```

To run `kubectl` without typing `sudo` every time on a node:
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
```

---

### Option B: Running from Your Mac Terminal (Recommended!)

You do **not** need to SSH into your nodes every time you want to inspect or manage the cluster. You can control the Pluto cluster directly from your Mac terminal!

#### 1. Install `kubectl` and helper tools on macOS:
```bash
brew install kubectl kubectx k9s
```

#### 2. Copy the K3s config from Hydra to your Mac:
```bash
mkdir -p ~/.kube

# Fetch the kubeconfig from Hydra via SSH
ssh hydra "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config-pluto

# Replace the loopback 127.0.0.1 with Hydra's IP or Tailscale domain
# (e.g., hydra.local, 192.168.1.x, or hydra's Tailscale IP)
sed -i '' 's/127.0.0.1/hydra/g' ~/.kube/config-pluto

# Secure permissions
chmod 600 ~/.kube/config-pluto

# Set KUBECONFIG in your ~/.zshrc:
echo 'export KUBECONFIG="$HOME/.kube/config-pluto"' >> ~/.zshrc
export KUBECONFIG="$HOME/.kube/config-pluto"
```

#### 3. Test from your Mac:
```bash
kubectl get nodes -o wide
```

---

## 3. The `kubectl` Grammar (How to Speak Kubernetes)

Every `kubectl` command follows a predictable sentence structure:

$$\textbf{kubectl} \quad \underbrace{\text{\textbf{<verb>}}}_{\text{What to do}} \quad \underbrace{\text{\textbf{<resource>}}}_{\text{Target type}} \quad \underbrace{\text{\textbf{[name]}}}_{\text{Specific item}} \quad \underbrace{\text{\textbf{[flags]}}}_{\text{Modifiers}}$$

### 1. Essential Verbs
| Verb | Purpose | Example |
| :--- | :--- | :--- |
| `get` | List resources in a tabular summary | `kubectl get pods` |
| `describe` | Deep-dive into detailed attributes, events, and health | `kubectl describe pod headlamp-xxx` |
| `logs` | Stream or print stdout/stderr output from a container | `kubectl logs headlamp-xxx` |
| `exec` | Run an interactive shell or command inside a container | `kubectl exec -it headlamp-xxx -- sh` |
| `apply` | Submit or update declared YAML/Kustomize files | `kubectl apply -k .` |
| `delete` | Terminate/remove a resource | `kubectl delete pod <name>` |
| `top` | View live CPU and Memory resource consumption | `kubectl top nodes` / `kubectl top pods` |
| `port-forward`| Tunnel a cluster port directly to your Mac `localhost` | `kubectl port-forward svc/headlamp 4466:80` |

### 2. Common Resource Types & Abbreviations
You don't need to type the full names; Kubernetes provides short aliases:

| Resource Type | Short Name | Description |
| :--- | :--- | :--- |
| `nodes` | `no` | Physical/virtual machines in the cluster (`hydra`, `styx`, `pluto`) |
| `namespaces` | `ns` | Logical isolation boundaries (`default`, `games`, `headlamp`) |
| `pods` | `po` | The smallest deployable unit (one or more co-located containers) |
| `deployments` | `deploy` | Controller for stateless apps that manages Pod replicas and rollouts |
| `statefulsets`| `sts` | Controller for stateful apps (databases, Minecraft) with stable identities |
| `services` | `svc` | Stable internal IP & DNS name that load-balances traffic across Pods |
| `persistentvolumeclaims` | `pvc` | Request for durable storage (e.g. NFS volume) |
| `persistentvolumes` | `pv` | Actual storage volume provisioned by the storage provider |
| `configmaps` | `cm` | Plaintext configuration files and environment key-values |
| `secrets` | `secret` | Base64-encoded encrypted credentials, tokens, and certificates |

---

## 4. Inspecting & Observing (The Read Operations)

### Finding Where Pods Run
The standard `kubectl get pods` hides the node name and IP address. Adding `-o wide` is essential:

```bash
# List all pods across the ENTIRE cluster, including which node they run on:
kubectl get pods -A -o wide

# Filter to a specific namespace:
kubectl get pods -n headlamp -o wide

# View only the node name directly:
kubectl get pods -n headlamp -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase
```

### Viewing All Workloads in a Namespace
```bash
# View Deployments, StatefulSets, Pods, and Services simultaneously:
kubectl get all -n games
```

### Inspecting Detailed Metadata & Events (`describe`)
When a pod is stuck, misbehaving, or failing to start, `describe` is your most valuable diagnostic command. **Always check the `Events:` section at the bottom of the output!**

```bash
kubectl describe pod -n headlamp <pod-name>
```

### Output Formatting Tricks
```bash
# Output raw live YAML (includes runtime status, IP, and assigned node):
kubectl get pod -n headlamp <pod-name> -o yaml

# Watch resources in real-time as they start or restart:
kubectl get pods -A -w

# Sort pods by node name:
kubectl get pods -A -o wide --sort-by='.spec.nodeName'
```

---

## 5. Debugging & Troubleshooting Runbook

When an application fails in Kubernetes, it almost always enters one of four states. Here is the diagnostic playbook:

```
                          ┌────────────────────────┐
                          │   Pod Not Ready/Crash  │
                          └───────────┬────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            ▼                         ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
   │ CrashLoopBackOff│       │     Pending     │       │ ErrImagePull    │
   └────────┬────────┘       └────────┬────────┘       └────────┬────────┘
            │                         │                         │
     Check App Logs            Check Scheduler           Check Image Tag
   kubectl logs <pod>       kubectl describe pod      kubectl describe pod
  kubectl logs --previous      (Events section)          (Events section)
```

### Scenario 1: `CrashLoopBackOff`
The container starts, but exits with an error code, and Kubernetes keeps restarting it.

1. **Read current logs**:
   ```bash
   kubectl logs -n <ns> <pod-name>
   ```
2. **If the pod just crashed and restarted, read the PREVIOUS run's logs**:
   ```bash
   kubectl logs -n <ns> <pod-name> --previous
   ```
3. **If the pod has multiple containers (e.g. init containers or sidecars)**:
   ```bash
   # List containers:
   kubectl get pod -n <ns> <pod-name> -o jsonpath='{.spec.containers[*].name}'

   # View logs of a specific container:
   kubectl logs -n <ns> <pod-name> -c <container-name>

   # View logs of an init container (e.g. init-kubeconfig in headlamp):
   kubectl logs -n <ns> <pod-name> -c init-kubeconfig
   ```

### Scenario 2: `Pending`
The pod cannot be scheduled or cannot attach storage.
1. Run `kubectl describe pod -n <ns> <pod-name>`.
2. Scroll to the bottom and read the **Events**:
   - `0/3 nodes available: insufficient cpu/memory`: Cluster is out of resources.
   - `node(s) didn't match Pod's node affinity/selector`: The pod requested a node label that doesn't exist.
   - `waiting for a volume to be created/attached`: The PersistentVolumeClaim (PVC) cannot bind to the NFS server. Check:
     ```bash
     kubectl get pvc -n <ns>
     kubectl describe pvc -n <ns> <pvc-name>
     ```

### Scenario 3: `ImagePullBackOff` / `ErrImagePull`
Kubernetes cannot download the container image.
- Typo in the image name or tag.
- Image registry is rate-limiting or requires authentication.
- Check with `kubectl describe pod -n <ns> <pod-name>` (look at the Image URL).

---

## 6. Interactive Operations (`exec`, `logs`, `port-forward`)

### 1. Opening an Interactive Shell inside a Container
Need to inspect the container filesystem, check networking, or test database connectivity?
```bash
# Standard shell:
kubectl exec -it -n <ns> <pod-name> -- /bin/sh

# If bash is installed:
kubectl exec -it -n <ns> <pod-name> -- /bin/bash

# Execute a one-off command without interactive shell:
kubectl exec -n <ns> <pod-name> -- ls -la /data
```

### 2. Live Log Streaming
```bash
# Stream live logs (-f / --follow):
kubectl logs -f -n headlamp <pod-name>

# Limit to the last 50 lines:
kubectl logs -n headlamp <pod-name> --tail=50

# Show timestamps:
kubectl logs -n headlamp <pod-name> --timestamps
```

### 3. Port Forwarding (Local Access Bypass)
You can securely forward ANY port inside the cluster to your local machine, completely bypassing ingress, tunnels, and firewalls:
```bash
# Forward Headlamp to your Mac's localhost:8080:
kubectl port-forward -n headlamp svc/headlamp 8080:4466

# Now open http://localhost:8080 in your Mac browser!
```

---

## 7. Pluto Fleet Node Scheduling & Placement

The Pluto cluster consists of 3 distinct hardware nodes:

| Node | Namesake | CPU / Hardware | Unique Role & Labels |
| :--- | :--- | :--- | :--- |
| **`hydra`** | Moon of Pluto | Intel Core i5-8500T (Intel QuickSync GPU) | Bootstrap master, `gpu.vendor=intel` |
| **`styx`** | Moon of Pluto | AMD Ryzen 5 Pro 4650U (ThinkPad T14) | Control-plane master, Battery-backed UPS |
| **`pluto`** | Dwarf Planet | AMD Ryzen 7 5825U (Beelink EQR5) | Compute & Game server node, `node.type=compute` |

### Why Did Headlamp Land on a Particular Node?

Take a look at `infrastructure/headlamp/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: headlamp
  namespace: headlamp
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: headlamp
          image: ghcr.io/headlamp-k8s/headlamp:v0.29.0
```

Notice:
1. **No `nodeSelector`**: There is no constraint specifying `kubernetes.io/hostname: pluto`.
2. **No `affinity`**: There is no preferred or required affinity rule.
3. **No node taints**: Because all 3 nodes run both control-plane and worker workloads in K3s, all 3 are schedulable.

**Conclusion**: The Kubernetes `kube-scheduler` selects whichever node has the most available CPU/memory headroom at the time the pod is created. If that node reboots, the pod automatically reschedules to another available node!

### How to Pin a Pod to a Specific Node (If Desired)

If you ever want a workload (like game servers on `pluto` or Plex/Jellyfin hardware transcoding on `hydra`) to run on an exact node:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node.type: compute            # Runs on Pluto
        # OR
        # gpu.vendor: intel           # Runs on Hydra
        # OR
        # kubernetes.io/hostname: hydra
```

---

## 8. The Ecosystem: `kubectl` vs Helm vs Headlamp vs Flux CD

There is often confusion around where each tool fits. Here is the definitive breakdown:

| Tool | What It Is | Primary Purpose | How Pluto Cluster Uses It |
| :--- | :--- | :--- | :--- |
| **`kubectl`** | **Command-Line Interface (CLI)** | Direct cluster interaction, live diagnostics, inspection, debugging, ad-hoc edits. | Your personal Swiss army knife for day-to-day inspection and troubleshooting. |
| **Helm** | **Package Manager & Templator** | Bundles complex multi-resource applications into parameterized, versioned charts (`values.yaml`). | Packages upstream applications (e.g., `nfs-subdir-external-provisioner`). |
| **Headlamp** | **Web UI Dashboard** | Visual observation of cluster state, node graphs, pod health, logs, and CRDs in a browser. | Read-only graphical overview accessible via Tailscale or browser. |
| **Flux CD** | **GitOps Controller** | Continuously synchronizes the cluster state with the Git repository (`main` branch). | Automated deployments. Commits to Git automatically deploy to the cluster. |

### Can Headlamp Replace Helm Completely?

> **No. Headlamp and Helm perform two fundamentally different jobs.**

- **Helm is a package installer and generator**: It takes a template with 50 configuration options, processes your `values.yaml`, and outputs valid Kubernetes manifests. It handles upgrades, rollbacks, and dependency graphs.
- **Headlamp is a dashboard/viewer**: It provides a visual UI to monitor running pods, view graphs, read logs, and browse resources.

While Headlamp does offer an optional catalog viewer or app installer plugin:
1. **GitOps Conflict**: Pluto is a **GitOps cluster**. If you click buttons in Headlamp to deploy or change an application, Flux CD will see that the cluster state differs from the Git repository and will **revert your changes** to maintain Git as the single source of truth.
2. **Templating Limitations**: Headlamp cannot replace the complex conditional templating that Helm charts provide for enterprise software.

**The Golden Workflow**:
- **Helm / Kustomize**: Define and package the application in Git (`pluto-cluster/apps/...`).
- **Flux CD**: Automatically reconcile and deploy the manifests into the cluster.
- **Headlamp**: View the cluster visually from your browser or tablet.
- **`kubectl`**: Perform deep troubleshooting, read logs, and execute debugging sessions from the terminal.

---

## 9. Pluto Cluster Quick Reference Cheat Sheet

### 🔭 Inspection Commands
```bash
# Which node is running what?
kubectl get pods -A -o wide

# Check cluster node health and IPs:
kubectl get nodes -o wide

# Check storage claims and volume binds:
kubectl get pvc -A

# Check services and external ingress:
kubectl get svc -A
```

### 🔍 Deep Inspection & Filtering
```bash
# Filter pods by label:
kubectl get pods -A -l app.kubernetes.io/name=headlamp

# View resource consumption (CPU & RAM):
kubectl top nodes
kubectl top pods -A --sort-by='memory'

# Check all resources in the games namespace:
kubectl get all -n games
```

### 🛠️ Debugging Commands
```bash
# Stream live logs:
kubectl logs -f -n <namespace> <pod-name>

# Inspect failure reasons & cluster events:
kubectl describe pod -n <namespace> <pod-name>

# Shell into a container:
kubectl exec -it -n <namespace> <pod-name> -- /bin/sh

# Restart a deployment gracefully without downtime:
kubectl rollout restart deployment/headlamp -n headlamp
```

### ⚡ Terminal Pro-Tip: Shell Aliases & Auto-Completion
Add this to your Mac's `~/.zshrc` to save thousands of keystrokes:

```bash
# Fast kubectl alias
alias k="kubectl"

# Quick namespace switcher
alias kgp="kubectl get pods -o wide"
alias kga="kubectl get pods -A -o wide"
alias kgn="kubectl get nodes -o wide"
alias kdp="kubectl describe pod"
alias kl="kubectl logs"
alias klf="kubectl logs -f"

# Autocompletion
source <(kubectl completion zsh)
complete -F __start_kubectl k
```
