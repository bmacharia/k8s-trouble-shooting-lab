# Lab 6.1 — CNI Deep Dive: Pod-to-Pod Connectivity Failure

## Symptom

`sender` pod in `team-alpha` cannot reach `receiver` pod in `team-beta`.
All pods show `Running`. No application errors. Traffic silently drops.

```
Error: dial tcp <receiver-ip>:8080: i/o timeout
```

## Lab Setup

```bash
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-workloads.yaml
kubectl apply -f 02-break.yaml

# Wait for pods to be Running
kubectl get pods -n team-alpha -n team-beta
```

## The Fundamental Question

> "Is this the CNI, a NetworkPolicy, a routing issue, or the application itself?"

Answer this first. Do not guess and apply fixes.

---

## Step 1 — Confirm the Symptom

```bash
# Get the receiver pod's IP
RECEIVER_IP=$(kubectl get pod receiver -n team-beta -o jsonpath='{.status.podIP}')
echo "Receiver IP: $RECEIVER_IP"

# Try to reach it from sender
kubectl exec -n team-alpha sender -- ping -c 3 $RECEIVER_IP

# Try TCP (ping works at L3, service issues are at L4)
kubectl exec -n team-alpha sender -- nc -zv $RECEIVER_IP 8080

# Try via the service DNS name
kubectl exec -n team-alpha sender -- curl -v --max-time 5 \
  http://receiver-svc.team-beta.svc.cluster.local:80
```

**What to look for:**
- `ping` succeeds but `nc` fails → L4/application problem
- Both fail → L3/CNI/NetworkPolicy problem
- DNS lookup fails before connection attempt → DNS problem

---

## Step 2 — Check for NetworkPolicy (Most Common Cause)

```bash
# Does team-beta have any NetworkPolicy?
kubectl get networkpolicy -n team-beta

# Describe each policy — read every selector carefully
kubectl describe networkpolicy -n team-beta

# KEY: If ANY NetworkPolicy exists targeting the receiver pod,
# then ALL traffic not matching a rule is BLOCKED.
# "No matching rule" ≠ "allowed" — it means "denied".
```

**The golden rule:**
```
If a pod has NO NetworkPolicy → allows all traffic
If a pod has ANY NetworkPolicy → denies all traffic EXCEPT what is explicitly allowed
```

---

## Step 3 — Verify Namespace Labels Match the Policy

```bash
# Check what labels team-alpha actually has
kubectl get namespace team-alpha --show-labels

# Check what labels the NetworkPolicy is LOOKING FOR
kubectl get networkpolicy receiver-ingress -n team-beta -o yaml | grep -A 10 "namespaceSelector"

# COMMON BUG: the policy says team=internal but the namespace has team=alpha
# These do not match → policy allows nothing → all traffic blocked
```

```bash
# Simulate what the scheduler/policy sees:
# "Show me all namespaces with label team=internal"
kubectl get namespaces -l team=internal
# If empty → the namespaceSelector matches NOTHING → no traffic allowed
```

---

## Step 4 — Verify Pod Labels Match the Policy

```bash
# Check what labels the sender pod actually has
kubectl get pod sender -n team-alpha --show-labels

# Check what the NetworkPolicy podSelector expects
kubectl get networkpolicy receiver-ingress -n team-beta -o jsonpath='{.spec.ingress[0].from[0].podSelector}'
```

---

## Step 5 — Trace the Packet Path (CNI-Level Investigation)

If there is NO NetworkPolicy and pods still cannot communicate, dig into the CNI:

```bash
# Find which node each pod is on
kubectl get pods -A -o wide | grep -E "sender|receiver"

# On the sender's node — map the veth pair to the pod
# (requires node access via kubectl debug or SSH)
kubectl debug node/<sender-node> -it --image=nicolaka/netshoot -- bash

  # Inside the debug pod (runs in host network namespace)
  ip route                          # Routing table — how does this node reach pod CIDRs?
  ip link show                      # All interfaces including veth pairs
  bridge link                       # Which veth is on which bridge?

  # Find the veth for the sender pod
  SENDER_IP=<sender-pod-ip>
  ip route get $SENDER_IP           # Which interface routes to sender?

  # Check iptables NAT rules (kube-proxy service rules)
  iptables -t nat -L KUBE-SERVICES -n --line-numbers
  iptables -t nat -L KUBE-POSTROUTING -n

# Packet capture on receiver's node
kubectl debug node/<receiver-node> -it --image=nicolaka/netshoot -- bash
  tcpdump -i any host <sender-pod-ip> -n   # Does traffic from sender arrive?
```

---

## Step 6 — Check Calico or Cilium Status (CNI Health)

**Calico:**
```bash
# Check Calico node pods
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide

# Any Calico node not ready = networking broken on that node
kubectl describe pod -n kube-system <calico-node-pod> | grep -A 10 "Conditions"

# Check BGP peer status (if using BGP routing)
kubectl exec -n kube-system <calico-node-pod> -- calicoctl node status
```

**Cilium:**
```bash
# Cilium status
kubectl exec -n kube-system <cilium-pod> -- cilium status

# Watch live network flows (requires Hubble)
kubectl exec -n kube-system <cilium-pod> -- hubble observe \
  --namespace team-alpha --namespace team-beta -f

# Policy verdict — was traffic dropped by policy?
kubectl exec -n kube-system <cilium-pod> -- hubble observe \
  --verdict DROPPED -f
```

---

## Log Analysis

```bash
# CoreDNS — is DNS working for the sender?
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# kube-proxy — are service rules correct?
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50

# CNI plugin logs — are there IP allocation or routing errors?
# Calico:
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Cilium:
kubectl logs -n kube-system -l k8s-app=cilium --tail=50
```

---

## Common Causes (in order of frequency)

| # | Cause | Signal | Fix |
|---|-------|--------|-----|
| 1 | NetworkPolicy `namespaceSelector` labels mismatch | Policy exists, no endpoints match | Fix labels on namespace or fix selector |
| 2 | NetworkPolicy `podSelector` labels mismatch | Policy exists, pod labels don't match | Fix pod labels or selector |
| 3 | Missing egress policy | Traffic leaves sender, never arrives | Add Egress rule to sender's namespace |
| 4 | CNI pod not running on a node | Pods on that node can't communicate | Restart CNI DaemonSet pod |
| 5 | IP pool exhausted | New pods get no IP | Expand CIDR or clean up terminated pods |
| 6 | MTU mismatch | Large packets drop, small ones succeed | Match MTU between CNI and host |
| 7 | iptables rule corruption | Random connectivity failures | Restart kube-proxy to rebuild rules |

---

## Resolution

```bash
# Apply the fix
kubectl apply -f 03-solution.yaml

# Verify the namespace label is now matched
kubectl get namespace team-alpha --show-labels
# Should show: team=alpha

# Confirm the NetworkPolicy now selects the right namespace
kubectl get networkpolicy receiver-ingress -n team-beta -o yaml

# Test connectivity
kubectl exec -n team-alpha sender -- nc -zv $RECEIVER_IP 8080
# Expected: Connection succeeded
```

---

## Prevention

```bash
# 1. Always label namespaces consistently at creation time
kubectl label namespace <ns> team=<teamname> env=<prod|staging|dev>

# 2. Test NetworkPolicy before applying to production
#    Use a dry-run tool like network-policy-viewer or cilium's policy trace
kubectl exec -n kube-system <cilium-pod> -- \
  cilium policy trace --src-k8s-pod team-alpha/sender --dst-k8s-pod team-beta/receiver

# 3. After applying a NetworkPolicy, ALWAYS run a connectivity check:
kubectl exec -n team-alpha sender -- nc -zv <receiver-ip> 8080

# 4. Add a team label requirement to your admission policy (Kyverno/OPA)
#    so namespaces cannot be created without required labels

# 5. Keep a "canary" pod in each namespace for fast connectivity testing
```

---

## Cleanup

```bash
kubectl delete -f 02-break.yaml
kubectl delete -f 01-workloads.yaml
kubectl delete -f 00-setup.yaml
```
