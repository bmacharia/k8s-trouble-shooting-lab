# Lab 7.1 — StatefulSets: Ordered, Persistent, and Stuck

## Symptoms

- `redis-0` is `Pending`. `redis-1` and `redis-2` have never been created.
- No error from `kubectl get pods -n databases` — just nothing beyond redis-0.
- PVC `data-redis-0` is also `Pending`.
- After fixing the PVC, the pods start but cannot address each other by hostname.

---

## Lab Setup

```bash
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-headless-service.yaml
kubectl apply -f 02-statefulset-broken.yaml

# Observe
kubectl get pods -n databases -w
kubectl get pvc -n databases -w
```

---

## How StatefulSets Are Different from Deployments

```
Deployment: all pods are interchangeable, start in any order
StatefulSet:
  - Pods have stable names: redis-0, redis-1, redis-2
  - Pods start IN ORDER: redis-0 must be Ready before redis-1 starts
  - Each pod gets its own PVC (from volumeClaimTemplates)
  - Pods have stable DNS names via headless service:
      redis-0.redis-headless.databases.svc.cluster.local
  - If redis-0 is Pending → redis-1 and redis-2 are never created
```

---

## Step 1 — Understand the Blocking Chain

```bash
# Check all pods
kubectl get pods -n databases

# Check PVCs
kubectl get pvc -n databases

# Check events — these tell you WHY redis-0 is pending
kubectl describe pod redis-0 -n databases
# Look at Events — you will see:
# "pod has unbound immediate PersistentVolumeClaims"

kubectl describe pvc data-redis-0 -n databases
# Look at Events — you will see:
# "no persistent volumes available for this claim"
# OR: "storageclass.storage.k8s.io "fast-ssd" not found"
```

---

## Step 2 — Diagnose the PVC Pending State

```bash
# What StorageClasses are available in this cluster?
kubectl get storageclass
# If "fast-ssd" is not listed → that's your problem

# What does the volumeClaimTemplate request?
kubectl get statefulset redis -n databases \
  -o jsonpath='{.spec.volumeClaimTemplates[0].spec}'

# What's the default StorageClass? (has annotation storageclass.kubernetes.io/is-default-class=true)
kubectl get storageclass -o json | \
  jq '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name'
```

---

## Step 3 — Diagnose the Headless Service

Even after pods start, inter-pod DNS will be broken. Check it now:

```bash
# Does the headless service exist?
kubectl get svc redis-headless -n databases

# Does it have endpoints? (it's headless so endpoints = pod IPs)
kubectl get endpoints redis-headless -n databases
# If "not found" or empty → the selector doesn't match the pods

# Compare service selector to pod labels
kubectl get svc redis-headless -n databases -o jsonpath='{.spec.selector}'
kubectl get pods -n databases --show-labels

# Test DNS resolution once pods are running
kubectl exec -n databases redis-0 -- nslookup redis-0.redis-headless.databases.svc.cluster.local
# If this fails → headless service selector is wrong
```

---

## Step 4 — Fix the PVC (StatefulSet PVC lifecycle rules)

```bash
# IMPORTANT: You CANNOT update volumeClaimTemplates on an existing StatefulSet.
# You must delete the StatefulSet (but NOT the PVCs automatically — default behavior keeps PVCs).
# Then recreate the StatefulSet with the correct StorageClass.

# Step 4a: Delete the StatefulSet (pods will be deleted, PVCs retained by default)
kubectl delete statefulset redis -n databases

# Step 4b: Delete the stuck PVC (it has no data yet anyway)
kubectl delete pvc data-redis-0 -n databases

# Step 4c: Verify PVC is gone
kubectl get pvc -n databases

# Step 4d: Apply the fixed StatefulSet (see 03-solution.yaml)
```

---

## Step 5 — Verify Ordering Behavior After Fix

```bash
# Watch pods start in strict order
kubectl get pods -n databases -w

# You should see:
# redis-0   0/1  Pending    (waiting for PVC)
# redis-0   0/1  Init:0/1   (PVC bound, container starting)
# redis-0   1/1  Running    (Ready)
# redis-1   0/1  Pending    (NOW redis-1 is created)
# redis-1   1/1  Running
# redis-2   0/1  Pending
# redis-2   1/1  Running

# Verify pod DNS names work
kubectl exec -n databases redis-0 -- \
  nslookup redis-1.redis-headless.databases.svc.cluster.local
# Should resolve to redis-1's pod IP
```

---

## Log Analysis

```bash
# StatefulSet controller logs (in controller-manager)
kubectl logs -n kube-system -l component=kube-controller-manager --tail=100 | \
  grep -i "statefulset\|redis"

# PVC provisioner logs
kubectl logs -n kube-system -l app=csi-provisioner --tail=50 | grep -i "fast-ssd\|error"
# OR for local-path provisioner (kind):
kubectl logs -n local-path-storage -l app=local-path-provisioner --tail=50

# Pod events
kubectl get events -n databases --sort-by='.lastTimestamp' | tail -20
```

---

## Common Causes

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | redis-0 Pending, others not created | PVC Pending blocks ordered startup | Fix StorageClass in volumeClaimTemplate |
| 2 | Pod starts but DNS fails | Headless service selector mismatch | Fix selector to match pod labels |
| 3 | PVC stuck in Pending | StorageClass doesn't exist | Use existing SC or omit for default |
| 4 | PVC stuck in Pending | provisioner pod not running | Check CSI/provisioner pods |
| 5 | Pod restarts repeatedly | readinessProbe fails on crash | Check app logs with `--previous` |
| 6 | Scale-down leaves PVCs | By design — PVCs are never auto-deleted | Manual cleanup: `kubectl delete pvc` |
| 7 | Pod can't reconnect to old PVC | PVC bound to different node | Check volume binding mode and topology |

---

## Key StatefulSet Behaviors to Know

```bash
# 1. PVCs are NEVER deleted when you delete a StatefulSet — by design
#    You must delete them manually if you want them gone
kubectl delete pvc -n databases -l app=redis

# 2. Scale down deletes pods in REVERSE order (redis-2 first, then redis-1)
kubectl scale statefulset redis -n databases --replicas=1
# redis-2 and redis-1 are deleted; redis-0 remains

# 3. Update strategy: RollingUpdate updates redis-2 first (reverse order)
kubectl rollout status statefulset/redis -n databases

# 4. OnDelete: pod is only updated when you manually delete it
kubectl patch statefulset redis -n databases \
  -p '{"spec":{"updateStrategy":{"type":"OnDelete"}}}'

# 5. Pause a rollout mid-way using partition
kubectl patch statefulset redis -n databases \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
# Only redis-2 gets the new version; redis-0 and redis-1 stay on old version
```

---

## Prevention

```bash
# 1. Always check available StorageClasses before writing StatefulSets
kubectl get storageclass

# 2. Use the default StorageClass (no storageClassName field) for portability
#    OR reference by name only after confirming it exists in target cluster

# 3. Test headless service resolution before running StatefulSet in production:
kubectl run dns-test --rm -it --restart=Never --image=busybox --namespace=databases -- \
  nslookup redis-0.redis-headless.databases.svc.cluster.local

# 4. Monitor PVC usage — PVCs are retained after StatefulSet deletion
kubectl get pvc -A | grep -v Bound   # find stuck or orphaned PVCs
```

---

## Cleanup

```bash
kubectl delete statefulset redis -n databases
kubectl delete pvc -n databases --all
kubectl delete namespace databases
```
