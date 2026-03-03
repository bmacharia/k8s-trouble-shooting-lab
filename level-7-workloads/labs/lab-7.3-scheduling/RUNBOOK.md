# Lab 7.3 — Scheduling: Taints, Affinity, Topology, and PDB

## Symptoms

- **Scenario A:** `gpu-workload` pod stuck in `Pending`. No scheduling events.
- **Scenario B:** `web-server` pod stuck in `Pending` after a maintenance window.
- **Scenario C:** `api-server` Deployment has 2/3 pods Running; 1 permanently `Pending`.
- **Scenario D:** `kubectl drain` hangs and never completes.

---

## Lab Setup

```bash
kubectl apply -f 01-scheduling-broken.yaml
kubectl apply -f 02-pdb-broken.yaml

# For Scenario B — simulate a maintenance taint on one of your worker nodes:
NODE=$(kubectl get nodes --no-headers | grep -v control-plane | head -1 | awk '{print $1}')
kubectl taint nodes $NODE maintenance=true:NoSchedule
echo "Tainted node: $NODE"
```

---

## The Scheduling Decision Tree

```
Can this pod be scheduled?
        │
        ▼
Are there nodes that pass the filter?
  └── nodeSelector: are labels present?
  └── nodeAffinity: do required expressions match?
  └── Taints: does the pod tolerate all node taints?
  └── Resources: is there enough cpu/memory?
  └── PVC: is the volume accessible from this node?
        │
        ▼
Among passing nodes, pick the best one:
  └── podAffinity/AntiAffinity preferred rules
  └── Resource balance
  └── Topology spread constraints
```

---

## Investigation — Scenario A (nodeSelector no match)

### Step 1 — Read the Events section

```bash
kubectl describe pod gpu-workload | grep -A 20 "Events:"
# Look for:
# Warning  FailedScheduling  ...  0/3 nodes are available:
#   3 node(s) didn't match Pod's node affinity/selector.
```

### Step 2 — Find what labels your nodes have

```bash
kubectl get nodes --show-labels

# Do any nodes have the label the pod requires?
kubectl get nodes -l accelerator=nvidia-tesla-v100
# If empty → no node matches → pod can never schedule
```

### Step 3 — Check the pod's nodeSelector

```bash
kubectl get pod gpu-workload -o jsonpath='{.spec.nodeSelector}'
# Output: {"accelerator":"nvidia-tesla-v100"}
```

### Step 4 — Options

```bash
# Option 1: Label a node to match (if the node actually has a GPU)
kubectl label node <node-name> accelerator=nvidia-tesla-v100

# Option 2: Change required to preferred in pod spec (soft preference)
# Edit the pod spec to use nodeAffinity with preferredDuringScheduling

# Option 3: Remove the nodeSelector entirely
kubectl patch pod gpu-workload \
  -p '{"spec":{"nodeSelector":null}}'
# Note: most pod spec fields are immutable — you may need to delete and recreate
```

---

## Investigation — Scenario B (taint not tolerated)

### Step 1 — Identify the blocking taint

```bash
kubectl describe pod web-server | grep -A 10 "Events:"
# Warning  FailedScheduling  ...
# 1 node(s) had taint {maintenance: true}, that the pod didn't tolerate.

# Which nodes have taints?
kubectl get nodes -o json | \
  jq '.items[] | {node: .metadata.name, taints: .spec.taints}'

# OR simpler:
kubectl describe nodes | grep -A 3 "Taints:"
```

### Step 2 — Check the pod's tolerations

```bash
kubectl get pod web-server -o jsonpath='{.spec.tolerations}'
# If empty → the pod tolerates nothing (except the default kubernetes.io/... taints)
```

### Step 3 — Taint effects and what they mean

```bash
# NoSchedule     — new pods without toleration won't be scheduled here
#                  existing pods on the node are NOT affected
# PreferNoSchedule — scheduler avoids this node but will use it if no other option
# NoExecute       — existing pods WITHOUT toleration are EVICTED
#                  this also affects running pods, not just new scheduling

# Check if any running pods are being evicted (NoExecute taint effect)
kubectl get pods --field-selector status.phase=Running -o wide | grep $NODE
```

### Step 4 — Fix approaches

```bash
# Approach A: Add toleration to the pod (if the pod should run on the tainted node)
# Add to pod spec:
# tolerations:
# - key: "maintenance"
#   operator: "Equal"
#   value: "true"
#   effect: "NoSchedule"

# Approach B: Remove the taint (if maintenance is done)
kubectl taint nodes $NODE maintenance=true:NoSchedule-
# The trailing "-" removes the taint
```

---

## Investigation — Scenario C (hard anti-affinity unsatisfiable)

### Step 1 — Check the pending pod

```bash
kubectl describe pod -l app=api-server | grep -B 5 -A 20 "Events:"
# Warning  FailedScheduling  ...
# 0/2 nodes are available:
#   2 node(s) didn't match pod anti-affinity rules.
```

### Step 2 — Understand required vs preferred

```bash
kubectl get deployment api-server -o yaml | grep -A 20 "affinity:"
# requiredDuringSchedulingIgnoredDuringExecution = HARD rule
# If no node satisfies it → pod stays Pending forever

# How many nodes do you have?
kubectl get nodes --no-headers | wc -l

# How many replicas?
kubectl get deployment api-server -o jsonpath='{.spec.replicas}'

# If replicas > worker-nodes → hard anti-affinity on hostname is impossible to satisfy
```

### Step 3 — Check topology spread constraints (the modern approach)

```bash
# Topology spread constraints are more flexible than hard anti-affinity:
# maxSkew: 1 — the difference between the most and least loaded zone/node is at most 1
# whenUnsatisfiable: DoNotSchedule — same as required anti-affinity
# whenUnsatisfiable: ScheduleAnyway — same as preferred anti-affinity

# View existing topology constraints
kubectl get deployment api-server -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'
```

---

## Investigation — Scenario D (PDB blocks drain)

### Step 1 — Attempt a drain and read the error

```bash
# Start a drain (this will hang with the broken PDB)
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=30s
# Error from server: error when evicting pods ...
# Cannot evict pod as it would violate the pod's disruption budget.
```

### Step 2 — Inspect the PDB

```bash
# Check PDB status
kubectl get pdb api-server-pdb
# NAME              MIN AVAILABLE  MAX UNAVAILABLE  ALLOWED DISRUPTIONS
# api-server-pdb    3              N/A              0
#
# ALLOWED DISRUPTIONS = 0 → NOTHING can be evicted

kubectl describe pdb api-server-pdb
# Check: Current / Desired / Allowed Disruptions
```

### Step 3 — Understand the math

```bash
# minAvailable: 3 with 3 replicas
# healthy pods = 3, minAvailable = 3 → allowedDisruptions = 3 - 3 = 0

# Safe PDB values:
# replicas=3, minAvailable=2  → allowedDisruptions=1  (can evict 1 at a time)
# replicas=3, maxUnavailable=1 → same as above, expressed differently
# replicas=3, minAvailable=1  → allowedDisruptions=2  (more aggressive)
```

---

## Log Analysis

```bash
# Scheduler logs — see exactly why a pod was rejected from each node
kubectl logs -n kube-system -l component=kube-scheduler --tail=200 | \
  grep -iE "gpu-workload|web-server|api-server|unable to schedule"

# Events — the most readable format
kubectl get events --sort-by='.lastTimestamp' | grep -E "FailedScheduling|Pending"

# Full events for a specific pod
kubectl describe pod <pod-name> | grep -A 30 "Events:"
```

---

## Common Causes

| # | Symptom | Cause | Signal |
|---|---------|-------|--------|
| 1 | Pod Pending — "didn't match node affinity" | nodeSelector label doesn't exist | `kubectl get nodes --show-labels` shows no match |
| 2 | Pod Pending — "had taint, pod didn't tolerate" | Missing toleration | `kubectl describe nodes` shows taint |
| 3 | 1 of N pods always Pending | Hard anti-affinity with fewer nodes than replicas | `requiredDuring` with `topologyKey: hostname` + replicas > nodes |
| 4 | kubectl drain hangs | PDB minAvailable = replica count | `kubectl get pdb` shows `ALLOWED DISRUPTIONS: 0` |
| 5 | Pods cluster on one node | Preferred affinity ignored due to resource imbalance | `kubectl top nodes` shows skewed resource usage |
| 6 | Pod pending "Insufficient memory" | Requesting more memory than any node has free | `kubectl describe node` → Allocatable vs Requested |

---

## Resolution

```bash
# Apply all fixes
kubectl delete pod gpu-workload web-server --ignore-not-found
kubectl delete deployment api-server --ignore-not-found
kubectl delete pdb api-server-pdb --ignore-not-found

kubectl apply -f 03-solution.yaml

# Remove the maintenance taint
kubectl taint nodes $NODE maintenance=true:NoSchedule-

# Verify all pods schedule
kubectl get pods -w

# Verify drain now works
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
kubectl uncordon $NODE
```

---

## Prevention

```bash
# 1. Check node labels before writing nodeSelector:
kubectl get nodes --show-labels

# 2. Prefer "preferred" over "required" for anti-affinity unless you KNOW
#    you will always have enough nodes

# 3. Use topologySpreadConstraints instead of podAntiAffinity for zone spreading:
#    It handles unequal node counts gracefully

# 4. PDB formula: minAvailable < replicas (always leave at least 1 disruption allowed)
#    Safe default: maxUnavailable: 1

# 5. After adding taints for maintenance, set a calendar reminder to remove them.
#    Or automate with a CronJob that removes taints after a time window.

# 6. Test PDB before node maintenance:
kubectl get pdb -A
kubectl get pdb -A -o json | \
  jq '.items[] | select(.status.disruptionsAllowed == 0) | .metadata.name'
# Any PDB with 0 allowed disruptions will block drain
```

---

## Cleanup

```bash
kubectl delete pod gpu-workload web-server --ignore-not-found
kubectl delete deployment api-server --ignore-not-found
kubectl delete pdb api-server-pdb --ignore-not-found
kubectl taint nodes $NODE maintenance=true:NoSchedule- 2>/dev/null || true
```
