# Lab 6.4 — NetworkPolicy: Zero-Trust Debugging

## Symptoms

After a security engineer implemented NetworkPolicy on the `production` namespace:
1. All DNS lookups fail from all pods in the namespace.
2. Frontend can reach backend (sometimes), but backend cannot reach the database.

---

## Lab Setup

```bash
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-three-tier-app.yaml
kubectl apply -f 02-policies-broken.yaml

kubectl rollout status deployment/frontend deployment/backend deployment/database -n production
```

---

## The Core NetworkPolicy Rules You Must Internalize

```
NO NetworkPolicy on a pod  →  ALL traffic allowed (ingress + egress)
ANY NetworkPolicy on a pod →  ALL traffic DENIED except what is explicitly permitted

NetworkPolicy is ADDITIVE:
  Multiple policies apply to the same pod? Rules are OR'd together.

policyTypes matters:
  - Ingress only  → only controls incoming; egress is still open
  - Egress only   → only controls outgoing; ingress is still open
  - Both          → you must explicitly allow BOTH directions
```

---

## Step 1 — Inventory All NetworkPolicies

```bash
# List all policies
kubectl get networkpolicy -n production

# Full detail on every policy — read carefully
kubectl describe networkpolicy -n production

# Which policies apply to a specific pod?
# A policy applies to a pod if its podSelector matches the pod's labels
kubectl get pod -n production -l tier=frontend --show-labels
kubectl get pod -n production -l tier=backend --show-labels
kubectl get pod -n production -l tier=database --show-labels
```

---

## Step 2 — Test Each Hop in the Communication Chain

```bash
# Set up variables
FRONTEND_POD=$(kubectl get pod -n production -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD=$(kubectl get pod -n production -l tier=backend -o jsonpath='{.items[0].metadata.name}')
DATABASE_POD=$(kubectl get pod -n production -l tier=database -o jsonpath='{.items[0].metadata.name}')

echo "Frontend: $FRONTEND_POD"
echo "Backend:  $BACKEND_POD"
echo "Database: $DATABASE_POD"

# Test 1: DNS resolution (should work, but will fail with Bug 1)
kubectl exec -n production $FRONTEND_POD -- nslookup backend-svc
kubectl exec -n production $BACKEND_POD -- nslookup database-svc

# Test 2: Frontend → Backend (by IP, bypassing DNS)
BACKEND_IP=$(kubectl get pod -n production $BACKEND_POD -o jsonpath='{.status.podIP}')
kubectl exec -n production $FRONTEND_POD -- nc -zv $BACKEND_IP 8080

# Test 3: Backend → Database (by IP)
DB_IP=$(kubectl get pod -n production $DATABASE_POD -o jsonpath='{.status.podIP}')
kubectl exec -n production $BACKEND_POD -- nc -zv $DB_IP 5432

# Test 4: Direct pod-to-pod, should be DENIED (verify security works)
kubectl exec -n production $FRONTEND_POD -- nc -zv $DB_IP 5432 --max-time 3
# Expected: timeout — frontend should NOT reach database directly
```

---

## Step 3 — Diagnose Bug 1 (DNS failure)

```bash
# Check if egress is restricted
kubectl get networkpolicy default-deny-egress -n production -o yaml

# Does it allow port 53?
kubectl get networkpolicy default-deny-egress -n production \
  -o jsonpath='{.spec.egress}' | python3 -m json.tool
# If output is "null" or empty → NO egress allowed, including DNS

# Confirm DNS failure
kubectl exec -n production $FRONTEND_POD -- nslookup kubernetes.default 2>&1
# Expected error: "connection timed out; no servers could be reached"

# Find where CoreDNS lives
kubectl get svc kube-dns -n kube-system
# Note the ClusterIP — pods need to reach this IP on port 53

# Test DNS connectivity directly by IP
KUBE_DNS_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
kubectl exec -n production $FRONTEND_POD -- nc -zuv $KUBE_DNS_IP 53 --max-time 3
# If this times out with egress deny → DNS egress is blocked
```

---

## Step 4 — Diagnose Bug 2 (Backend → Database blocked)

```bash
# Read the policy that controls database ingress
kubectl get networkpolicy allow-backend-to-database -n production -o yaml

# What label does the policy expect the source pod to have?
kubectl get networkpolicy allow-backend-to-database -n production \
  -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels}'
# Output: {"app":"api-service"}  ← this is the bug

# What labels does the backend pod actually have?
kubectl get pod -n production -l tier=backend --show-labels
# Output shows: app=backend, tier=backend

# The policy expects "app=api-service" but backend has "app=backend"
# These do not match → database ingress is blocked for backend pods

# Verify: does any pod have the label the policy expects?
kubectl get pods -n production -l app=api-service
# Output: No resources found → the policy allows NO pods
```

---

## Step 5 — Cilium Policy Trace (if using Cilium CNI)

```bash
# Trace what Cilium allows/denies between specific pods
FRONTEND_IDENTITY=$(kubectl get pod $FRONTEND_POD -n production \
  -o jsonpath='{.metadata.uid}')

kubectl exec -n kube-system <cilium-pod> -- \
  cilium policy trace \
  --src-k8s-pod production/$FRONTEND_POD \
  --dst-k8s-pod production/$BACKEND_POD \
  --dport 8080

# Trace and watch live drops
kubectl exec -n kube-system <cilium-pod> -- \
  hubble observe --verdict DROPPED --namespace production -f
```

---

## Log Analysis

```bash
# Check pod logs for connection errors
kubectl logs -n production $BACKEND_POD --tail=50 | grep -iE "error|timeout|refused"

# Check CoreDNS logs for denied queries
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Check events for NetworkPolicy-related issues
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20

# Calico: check policy enforcement logs
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep -i "drop\|deny"
```

---

## Common Causes

| # | Symptom | Cause | Check |
|---|---------|-------|-------|
| 1 | All DNS fails after adding egress deny | No egress rule for port 53 | `kubectl get netpol -o yaml` → check egress.ports for 53 |
| 2 | Specific pod can't reach destination | Wrong `podSelector` labels in from/to | Compare policy labels to `kubectl get pod --show-labels` |
| 3 | Nothing can reach a pod | Ingress policy exists with no matching rules | `kubectl describe netpol` → check `Ingress:` section |
| 4 | Policy allows but traffic still blocked | Egress policy missing (need BOTH directions) | Check if source pod has egress policy permitting the traffic |
| 5 | Works in dev, fails in prod | Different namespace labels | `kubectl get ns --show-labels` in each environment |
| 6 | Random failures, not consistent | Pod label changed during deploy | Rolling update changed label temporarily |

---

## Resolution

```bash
# Remove broken policies
kubectl delete -f 02-policies-broken.yaml

# Apply correct policies
kubectl apply -f 03-solution.yaml

# Validate fix — run all connectivity checks
kubectl exec -n production $FRONTEND_POD -- nslookup backend-svc
kubectl exec -n production $FRONTEND_POD -- nc -zv $BACKEND_IP 8080
kubectl exec -n production $BACKEND_POD -- nc -zv $DB_IP 5432

# Validate security — these should STILL be blocked
kubectl exec -n production $FRONTEND_POD -- nc -zv $DB_IP 5432 --max-time 3
# Expected: timeout — policy is correct, security intact
```

---

## The NetworkPolicy Checklist (use before every deploy)

```bash
# For every NetworkPolicy you write, verify:

# 1. DNS is allowed in egress
kubectl get netpol -n <ns> -o json | \
  jq '.items[].spec.egress[]?.ports[]? | select(.port == 53)'

# 2. Both ingress AND egress are addressed for each communication path
#    Frontend → Backend requires:
#    - Ingress on backend (from frontend)
#    - Egress on frontend (to backend)

# 3. The podSelector labels actually exist on pods
kubectl get pods -n <ns> --show-labels | grep <expected-label>

# 4. Test from BOTH sides after applying
kubectl exec <source-pod> -- nc -zv <dest-ip> <port>
```

---

## Prevention

```bash
# 1. ALWAYS allow DNS egress when using default-deny-egress:
#    - port: 53 (UDP + TCP) to kube-dns namespace

# 2. Label pods with both app= and tier= from day one — use both in policies

# 3. Use the netassert or network-policy-validator tool to unit-test policies

# 4. Apply policies to staging first, run full connectivity matrix before prod

# 5. Document the intended communication matrix as a comment in the policy file:
#    # ALLOWED: frontend→backend:8080, backend→database:5432
#    # DENIED:  frontend→database (direct), database→any (no egress)
```

---

## Cleanup

```bash
kubectl delete namespace production
```
