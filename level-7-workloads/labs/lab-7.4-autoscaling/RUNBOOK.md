# Lab 7.4 — HPA: Autoscaling That Doesn't Scale

## Symptoms

- **Symptom A:** HPA exists. High CPU load on pods. Replica count never increases.
- **Symptom B:** After load drops, replicas scale down from 10 → 2 in seconds.
  The next wave of traffic hits before pods start up → latency spike → outage.
- **Symptom C:** `kubectl get hpa` shows `<unknown>/50%` for current CPU.

---

## Lab Setup

```bash
kubectl apply -f 01-deployment.yaml
kubectl apply -f 02-hpa-broken.yaml

kubectl rollout status deployment/web-app -n autoscale-lab
kubectl get hpa -n autoscale-lab -w
```

---

## Prerequisites Check

```bash
# HPA requires metrics-server — check if it's installed
kubectl get deployment metrics-server -n kube-system
# If not found → install it:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify metrics-server is working
kubectl top nodes
kubectl top pods -n autoscale-lab
# If these return data → metrics-server is working
# If "Error from server: Metrics API not available" → metrics-server not ready
```

---

## Step 1 — Read HPA Status (the most important command)

```bash
kubectl describe hpa web-app-hpa -n autoscale-lab

# KEY SECTIONS:
# Conditions:
#   AbleToScale     True|False — can the HPA change replica count?
#   ScalingActive   True|False — is there a metric being successfully read?
#   ScalingLimited  True|False — at min or max replicas?
#
# Events:
#   SuccessfulRescale → HPA scaled
#   FailedGetScale    → HPA can't find the target (wrong name, wrong kind)
#   DesiredReplicas   → what HPA wants vs what it has
```

---

## Step 2 — Diagnose "HPA not scaling up"

```bash
# Check ScalingActive condition
kubectl get hpa web-app-hpa -n autoscale-lab -o yaml | \
  grep -A 30 "conditions:"

# Condition: ScalingActive=False, Reason=FailedGetScale
# → The HPA cannot find the target workload
# → Check the scaleTargetRef name

# What name does HPA reference?
kubectl get hpa web-app-hpa -n autoscale-lab \
  -o jsonpath='{.spec.scaleTargetRef.name}'

# What is the actual deployment name?
kubectl get deployment -n autoscale-lab
# Compare the two — any typo breaks HPA entirely
```

### Step 3 — Diagnose `<unknown>` current metrics

```bash
# HPA shows: TARGETS: <unknown>/50%

# Cause 1: metrics-server not running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Cause 2: Pods have no resource requests set
kubectl get deployment web-app -n autoscale-lab \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
# If requests is empty → HPA cannot calculate utilization percentage

# Cause 3: metrics-server needs --kubelet-insecure-tls in some environments
kubectl get deployment metrics-server -n kube-system -o yaml | grep insecure-tls
```

### Step 4 — Diagnose the scale-down thrashing

```bash
# Check the behavior section
kubectl get hpa web-app-hpa -n autoscale-lab \
  -o jsonpath='{.spec.behavior.scaleDown}'

# If stabilizationWindowSeconds: 0 → scales down immediately when load drops
# Healthy value: 300 seconds (5 minutes) — waits before deciding to scale down

# Watch HPA events to see rapid scale-down
kubectl get events -n autoscale-lab --sort-by='.lastTimestamp' | \
  grep -i "SuccessfulRescale"
```

---

## Load Testing (Generate Traffic to See HPA in Action)

```bash
# Install hey (HTTP load generator) in a pod
kubectl run load-gen --rm -it --restart=Never \
  --image=williamyeh/hey -- \
  /usr/local/bin/hey -z 2m -c 50 http://web-app-svc.autoscale-lab.svc.cluster.local/

# In another terminal — watch HPA respond
kubectl get hpa web-app-hpa -n autoscale-lab -w

# Watch pods being added
kubectl get pods -n autoscale-lab -w
```

---

## Log Analysis

```bash
# HPA controller logs (kube-controller-manager)
kubectl logs -n kube-system -l component=kube-controller-manager --tail=200 | \
  grep -i "hpa\|horizontalpodautoscal\|web-app"

# Metrics server logs
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=100

# HPA events (most readable)
kubectl describe hpa web-app-hpa -n autoscale-lab | tail -20

# Current metric values — what HPA is actually seeing
kubectl get hpa web-app-hpa -n autoscale-lab -o yaml | grep -A 20 "currentMetrics:"
```

---

## Common Causes

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | HPA never scales | Wrong `scaleTargetRef.name` | Match name exactly to Deployment |
| 2 | `<unknown>` current metric | No resource `requests` on containers | Add CPU/memory requests |
| 3 | `<unknown>` current metric | metrics-server not installed/running | Install or restart metrics-server |
| 4 | HPA at max, won't go higher | `maxReplicas` reached | Increase maxReplicas or add nodes |
| 5 | Scale down too aggressive | `stabilizationWindowSeconds: 0` | Set 300s (5 minutes) for scale down |
| 6 | Pods added, CPU still high | HPA targeting wrong metric (p50 vs p99) | Use proper averaging metric |
| 7 | VPA and HPA both installed | Conflict — they fight each other | Never run both on same Deployment |

---

## Resolution

```bash
kubectl delete hpa web-app-hpa -n autoscale-lab
kubectl apply -f 03-solution.yaml

# Verify HPA is now active
kubectl describe hpa web-app-hpa -n autoscale-lab | grep -A 5 "Conditions:"
# ScalingActive should be True

kubectl get hpa web-app-hpa -n autoscale-lab
# TARGETS should show actual CPU% / 50%

# Run load test and watch it scale
kubectl run load-gen --rm -it --restart=Never \
  --image=williamyeh/hey -- \
  /usr/local/bin/hey -z 60s -c 20 http://web-app-svc.autoscale-lab.svc.cluster.local/

kubectl get hpa web-app-hpa -n autoscale-lab -w
```

---

## Prevention

```bash
# 1. Always verify HPA immediately after creation:
kubectl describe hpa <name> -n <namespace> | grep -E "ScalingActive|FailedGet"

# 2. HPA checklist before going to production:
#    [ ] scaleTargetRef name matches Deployment/StatefulSet exactly
#    [ ] All containers have cpu requests set
#    [ ] metrics-server is running
#    [ ] stabilizationWindowSeconds >= 180 for scale-down
#    [ ] maxReplicas is realistic (can your cluster nodes support it?)
#    [ ] Test with load-gen to confirm it actually scales

# 3. Never run HPA and VPA (in Auto mode) on the same Deployment
#    VPA in Initial mode (sets requests at pod start) is safe with HPA

# 4. Use custom metrics for more meaningful autoscaling:
#    CPU is a proxy — requests per second or queue depth are often better signals
```

---

## Cleanup

```bash
kubectl delete namespace autoscale-lab
```
