# Level 3: Kubernetes Core Troubleshooting

*"Kubernetes doesn't hide problems — it just puts them in different places."*

**Time estimate: 25-30 hours**

---

## 3.1 Kubernetes Architecture — What Breaks Where

```
┌─────────────────────────────────────────────────────────────────────┐
│                    KUBERNETES ARCHITECTURE                           │
│                  (What breaks and where to look)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  CONTROL PLANE (brain of the cluster)                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ etcd           — Cluster state database                      │   │
│  │   BREAKS: disk full, quorum loss, slow I/O, cert expiry      │   │
│  │   CHECK: etcdctl endpoint health, etcdctl alarm list         │   │
│  │                                                              │   │
│  │ kube-apiserver — REST API, all communication goes through it │   │
│  │   BREAKS: cert expiry, OOM, too many requests, etcd issues   │   │
│  │   CHECK: kubectl cluster-info, API server logs               │   │
│  │                                                              │   │
│  │ kube-scheduler — Assigns pods to nodes                       │   │
│  │   BREAKS: resource exhaustion, taint/tolerance mismatch      │   │
│  │   CHECK: kubectl describe pod (Events section)               │   │
│  │                                                              │   │
│  │ kube-controller-manager — Reconciliation loops               │   │
│  │   BREAKS: API server connectivity, resource quota            │   │
│  │   CHECK: controller-manager logs                             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  WORKER NODE (runs your workloads)                                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ kubelet        — Node agent, manages pods on this node       │   │
│  │   BREAKS: disk pressure, memory pressure, PID pressure       │   │
│  │   CHECK: systemctl status kubelet, journalctl -u kubelet     │   │
│  │                                                              │   │
│  │ kube-proxy     — Network rules (iptables/ipvs)               │   │
│  │   BREAKS: iptables corruption, stale rules                   │   │
│  │   CHECK: iptables -L -t nat, kube-proxy logs                 │   │
│  │                                                              │   │
│  │ Container Runtime (containerd/CRI-O)                         │   │
│  │   BREAKS: disk full, socket issues, image pull failures      │   │
│  │   CHECK: crictl ps, crictl logs, systemctl status containerd │   │
│  │                                                              │   │
│  │ CNI Plugin (Calico/Cilium/Flannel)                           │   │
│  │   BREAKS: network overlay issues, IP exhaustion              │   │
│  │   CHECK: CNI pod logs, ip route, iptables                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3.2 kubectl — Your Primary Troubleshooting Tool

### Essential kubectl Commands

```bash
# ──────────────────────────────────────
# Cluster Health
# ──────────────────────────────────────
kubectl cluster-info                        # API server and CoreDNS endpoints
kubectl get componentstatuses               # Control plane health (deprecated but useful)
kubectl get nodes -o wide                   # Node status + IPs + versions
kubectl top nodes                           # Node CPU/memory usage
kubectl get events --sort-by='.lastTimestamp' -A  # All cluster events

# ──────────────────────────────────────
# Pod Investigation (90% of troubleshooting)
# ──────────────────────────────────────
kubectl get pods -A                         # All pods in all namespaces
kubectl get pods -o wide                    # Include node and IP
kubectl get pods --field-selector status.phase!=Running  # Non-running pods

# THE MOST IMPORTANT COMMAND — describe:
kubectl describe pod <pod-name>
# Look at:
#   Conditions  — Ready, Initialized, ContainersReady
#   Events      — Scheduling, pulling, starting, errors
#   State       — Running, Waiting (with reason), Terminated (with reason)

# Logs
kubectl logs <pod-name>                     # Current logs
kubectl logs <pod-name> --previous          # Previous container (after crash)
kubectl logs <pod-name> -c <container>      # Specific container
kubectl logs <pod-name> -f                  # Follow (stream)
kubectl logs <pod-name> --tail=100          # Last 100 lines
kubectl logs <pod-name> --since=1h          # Last hour
kubectl logs -l app=nginx                   # All pods with label app=nginx

# Execute into pods
kubectl exec -it <pod-name> -- /bin/bash    # Shell into pod
kubectl exec -it <pod-name> -- /bin/sh      # If bash unavailable
kubectl exec <pod-name> -- cat /etc/resolv.conf  # Run single command
kubectl exec <pod-name> -- env              # View environment variables

# Copy files
kubectl cp <pod-name>:/path/to/file ./local-file
kubectl cp ./local-file <pod-name>:/path/to/file

# ──────────────────────────────────────
# Resource Investigation
# ──────────────────────────────────────
kubectl get deploy,rs,pods -l app=myapp     # Full ownership chain
kubectl get all -n <namespace>              # All resources in namespace
kubectl api-resources                       # All available resource types

# Output Formatting
kubectl get pods -o yaml                    # Full YAML definition
kubectl get pods -o json                    # Full JSON
kubectl get pods -o jsonpath='{.items[*].metadata.name}'  # Extract fields
kubectl get pods -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName"

# ──────────────────────────────────────
# Diff and Dry Run
# ──────────────────────────────────────
kubectl diff -f deployment.yaml             # Show what would change
kubectl apply -f deployment.yaml --dry-run=server  # Validate server-side
kubectl apply -f deployment.yaml --dry-run=client  # Validate client-side
```

### The kubectl Debug Command

```bash
# Debug running pods with ephemeral containers
kubectl debug -it <pod-name> --image=busybox --target=<container>

# Debug a node
kubectl debug node/<node-name> -it --image=ubuntu

# Create a debug copy of a pod
kubectl debug <pod-name> -it --copy-to=debug-pod --container=debug \
  --image=nicolaka/netshoot
```

---

## 3.3 Pod Troubleshooting — The Complete Flowchart

```
Pod is not working
        │
        ▼
   What status?
   ┌─────┴─────────────────────────────────────────────────┐
   │              │              │              │           │
   ▼              ▼              ▼              ▼           ▼
Pending     CrashLoopBack  ImagePullBack   Error      Running but
                Off          Off                      not working
   │              │              │              │           │
   ▼              ▼              ▼              ▼           ▼
Check:        Check:         Check:         Check:      Check:
-Scheduling   -Pod logs      -Image name    -Pod logs   -Readiness
-Resources    -Previous logs -Registry auth -Events      probe
-Taints       -OOM kills    -Network        -describe   -Service
-Node         -Exit codes   -Pull secret               -Endpoints
 capacity     -Probes                                   -DNS
-PVC          -Resources                                -Network
 binding      -Command                                   Policy
```

### Pending Pods

```bash
# Step 1: What does describe say?
kubectl describe pod <pod-name>

# Common Pending reasons:

# 1. Insufficient resources
# Event: "0/3 nodes are available: 3 Insufficient cpu"
# Fix: Check node capacity or reduce resource requests
kubectl top nodes
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# 2. Unschedulable — taints and tolerations
# Event: "0/3 nodes are available: 3 node(s) had taint {key: value}"
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, taints: .spec.taints}'
# Fix: Add tolerations to the pod spec or remove taints
kubectl taint nodes <node> key=value:NoSchedule-  # Remove taint (note the -)

# 3. PVC not bound
# Event: "persistentvolumeclaim not found" or "unbound PVC"
kubectl get pvc
kubectl describe pvc <pvc-name>
# Fix: Check StorageClass, provisioner, or create the PV

# 4. Node selector / affinity mismatch
kubectl get nodes --show-labels
# Fix: Add matching labels to nodes or adjust pod spec

# 5. Pod quota exceeded
kubectl get resourcequota -A
```

### CrashLoopBackOff

```bash
# The pod starts, crashes, Kubernetes restarts it, it crashes again...

# Step 1: Check logs from the CURRENT attempt
kubectl logs <pod-name>

# Step 2: Check logs from the PREVIOUS crash
kubectl logs <pod-name> --previous

# Step 3: Check the exit code
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'

# Common exit codes:
# 0   — Completed successfully (shouldn't be in a Deployment)
# 1   — Application error
# 126 — Permission denied (command not executable)
# 127 — Command not found (wrong entrypoint/command)
# 128 — Invalid exit argument
# 137 — SIGKILL (OOM killed or exceeded memory limit)
# 139 — SIGSEGV (segmentation fault)
# 143 — SIGTERM (graceful shutdown)

# Exit code 137 — OOM investigation:
kubectl describe pod <pod-name> | grep -A 3 "Last State"
# If Reason: OOMKilled → increase memory limits
dmesg | grep -i oom              # Check node-level OOM

# Step 4: Common CrashLoopBackOff causes and fixes:

# Wrong command:
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].command}'
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].args}'

# Missing config/env:
kubectl exec -it <pod-name> -- env
kubectl describe pod <pod-name> | grep -A 20 "Environment"

# Failing health check:
kubectl describe pod <pod-name> | grep -A 10 "Liveness"
# Fix: Increase initialDelaySeconds or fix the health endpoint
```

### ImagePullBackOff

```bash
# Step 1: Get the error details
kubectl describe pod <pod-name> | grep -A 5 "Events"

# Common causes:

# 1. Wrong image name
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].image}'
# Fix: Correct the image name

# 2. Image doesn't exist
# "manifest unknown" or "not found"
# Fix: Verify the tag exists in the registry

# 3. Authentication required
# "unauthorized" or "access denied"
# Fix: Create and attach an image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com

# 4. Network issue (can't reach registry)
kubectl debug node/<node-name> -it --image=busybox -- nslookup registry.example.com
```

**Lab: [lab-3.1-broken-pods.yaml](labs/lab-3.1-broken-pods.yaml)** — Fix 5 broken pods

---

## 3.4 Service and Networking Troubleshooting

### The Service Connectivity Chain

```
Client → DNS → Service (ClusterIP) → Endpoints → Pod IP:Port
         │         │                      │            │
         │         │                      │            └── Is the container
         │         │                      │                listening?
         │         │                      │
         │         │                      └── Are there endpoints?
         │         │                           (selector matches pods?)
         │         │
         │         └── Does the Service exist?
         │              Correct port?
         │
         └── Does DNS resolve?
              (CoreDNS running?)
```

### Debugging Services

```bash
# ──────────────────────────────────────
# Step 1: Does the Service exist?
# ──────────────────────────────────────
kubectl get svc <service-name> -n <namespace>

# ──────────────────────────────────────
# Step 2: Does the Service have endpoints?
# ──────────────────────────────────────
kubectl get endpoints <service-name> -n <namespace>
# If ENDPOINTS is <none> → selector doesn't match any pods!

# Compare Service selector with Pod labels:
kubectl get svc <service-name> -o jsonpath='{.spec.selector}'
kubectl get pods -l <key>=<value>   # Use the selector labels

# ──────────────────────────────────────
# Step 3: Does DNS resolve?
# ──────────────────────────────────────
kubectl run dns-test --rm -i --restart=Never --image=busybox -- \
  nslookup <service-name>.<namespace>.svc.cluster.local

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# ──────────────────────────────────────
# Step 4: Can you reach the pod directly?
# ──────────────────────────────────────
# Get pod IP
POD_IP=$(kubectl get pod <pod-name> -o jsonpath='{.status.podIP}')

# Test from another pod
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -- \
  curl -v http://$POD_IP:<container-port>

# ──────────────────────────────────────
# Step 5: Is there a NetworkPolicy blocking traffic?
# ──────────────────────────────────────
kubectl get networkpolicy -A
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### DNS Troubleshooting Checklist

```bash
# 1. Is CoreDNS running?
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Check CoreDNS logs for errors
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 3. Test DNS from inside a pod
kubectl run dnsutils --rm -i --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dnsutils -- \
  bash -c "
    echo '=== /etc/resolv.conf ==='
    cat /etc/resolv.conf
    echo ''
    echo '=== nslookup kubernetes ==='
    nslookup kubernetes.default.svc.cluster.local
    echo ''
    echo '=== nslookup external ==='
    nslookup google.com
  "

# 4. DNS service format:
# <service-name>.<namespace>.svc.cluster.local
# <pod-ip-dashed>.<namespace>.pod.cluster.local
```

**Lab: [lab-3.2-service-debug.yaml](labs/lab-3.2-service-debug.yaml)** — Fix a broken service chain

---

## 3.5 Node Troubleshooting

```bash
# ──────────────────────────────────────
# Node Status Investigation
# ──────────────────────────────────────
kubectl get nodes
kubectl describe node <node-name>

# Key sections in describe node:
# Conditions:
#   Ready            — kubelet is healthy, can accept pods
#   MemoryPressure   — node running low on memory
#   DiskPressure     — node running low on disk
#   PIDPressure      — too many processes
#   NetworkUnavailable — network not configured

# A node goes NotReady when:
# - kubelet crashes or is stopped
# - Container runtime fails
# - Network connectivity lost to API server
# - Certificate expired

# ──────────────────────────────────────
# Investigating NotReady Nodes
# ──────────────────────────────────────
# SSH to the node, then:
sudo systemctl status kubelet
sudo journalctl -u kubelet --since "10 min ago" | tail -50

# Common kubelet issues:
# 1. Can't reach API server
curl -k https://<control-plane-ip>:6443/healthz

# 2. Certificate issues
ls -la /var/lib/kubelet/pki/
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates

# 3. Container runtime not running
sudo systemctl status containerd
sudo crictl ps

# 4. Disk pressure
df -h
# If /var/lib/containerd or /var/lib/kubelet is full → eviction

# ──────────────────────────────────────
# Node Maintenance
# ──────────────────────────────────────
# Gracefully remove workloads before maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Node is now cordoned (no new pods) and drained (existing pods moved)

# After maintenance, allow pods again
kubectl uncordon <node-name>

# Just prevent new pods (without draining)
kubectl cordon <node-name>
```
