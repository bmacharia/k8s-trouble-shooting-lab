# Lab 6.2 — Service Networking: ClusterIP, NodePort, and ExternalTrafficPolicy

## Symptoms

**Symptom A:** Internal pods get `Connection refused` hitting `backend-svc`.
**Symptom B:** External traffic hits the NodePort on some nodes and works; on others it silently drops.

---

## Lab Setup

```bash
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-backend.yaml
kubectl apply -f 02-services-broken.yaml

kubectl rollout status deployment/backend -n shop
```

---

## The Service Connection Chain

```
Client
  │
  ▼
Service DNS (CoreDNS)
  │  resolves to ClusterIP
  ▼
kube-proxy iptables/IPVS NAT rule
  │  DNAT to one of the Endpoints
  ▼
Pod IP:containerPort
  │
  ▼
Application process listening on that port
```

**Every link in this chain can break independently.**

---

## Investigation — Symptom A (Connection Refused on ClusterIP)

### Step 1 — Confirm the service exists and has endpoints

```bash
# Does the service exist?
kubectl get svc backend-svc -n shop

# Does it have endpoints? (if empty → selector mismatch)
kubectl get endpoints backend-svc -n shop

# Full detail
kubectl describe svc backend-svc -n shop
```

**Expected output with a selector bug:** `Endpoints: <none>`
**Expected output with a targetPort bug:** `Endpoints: 10.x.x.x:80,10.x.x.x:80,10.x.x.x:80` (but port 80 is wrong)

### Step 2 — Verify the selector matches pods

```bash
# What selector does the service use?
kubectl get svc backend-svc -n shop -o jsonpath='{.spec.selector}'
# Output: {"app":"backend","tier":"api"}

# Are there pods matching ALL of those labels?
kubectl get pods -n shop -l app=backend,tier=api
# If empty → labels on the pod don't match. Check with --show-labels
kubectl get pods -n shop --show-labels
```

### Step 3 — Find the real port the container listens on

```bash
# What port does the service send traffic to?
kubectl get svc backend-svc -n shop -o jsonpath='{.spec.ports[0].targetPort}'

# What port does the container actually expose?
kubectl get deployment backend -n shop \
  -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'

# They must match. If they don't, connections will be "Connection refused".

# Confirm by exec-ing into a pod and checking what's listening
kubectl exec -n shop deployment/backend -- netstat -tlnp
# OR
kubectl exec -n shop deployment/backend -- ss -tlnp
```

### Step 4 — Test direct pod connectivity (bypass the service)

```bash
# Get a pod IP
POD_IP=$(kubectl get pods -n shop -l app=backend -o jsonpath='{.items[0].status.podIP}')
echo "Pod IP: $POD_IP"

# Test directly to the pod — no service involved
kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- \
  curl -v http://$POD_IP:8080

# If this works but the service doesn't → problem is in the service (targetPort, selector)
# If this also fails → problem is in the pod (app not listening, crashloop, readiness)
```

### Step 5 — Trace the iptables NAT rules

```bash
# Find the ClusterIP
CLUSTER_IP=$(kubectl get svc backend-svc -n shop -o jsonpath='{.spec.clusterIP}')
echo "ClusterIP: $CLUSTER_IP"

# On a node, find the KUBE-SERVICES iptables chain entry for this service
# (requires node access)
kubectl debug node/<node-name> -it --image=nicolaka/netshoot -- bash
  iptables -t nat -L KUBE-SERVICES -n | grep $CLUSTER_IP
  # Follow the chain name to see load balancing rules
  iptables -t nat -L KUBE-SVC-<hash> -n
  # Follow to individual endpoint rules
  iptables -t nat -L KUBE-SEP-<hash> -n
  # The DNAT line shows the actual pod IP:port being used
```

---

## Investigation — Symptom B (NodePort drops traffic on some nodes)

### Step 1 — Understand externalTrafficPolicy

```bash
# Check the policy
kubectl get svc backend-nodeport -n shop -o jsonpath='{.spec.externalTrafficPolicy}'

# With externalTrafficPolicy: Local:
# - Traffic to a node that HAS a backend pod → works
# - Traffic to a node that has NO backend pod → DROPPED (not forwarded)
# This is by design for source IP preservation — but dangerous with uneven pod distribution
```

### Step 2 — Map pods to nodes

```bash
# See which nodes have backend pods
kubectl get pods -n shop -l app=backend -o wide

# Check node count vs pod count
kubectl get nodes
# If 3 nodes but replicas=2, one node will always drop NodePort traffic
```

### Step 3 — Test from outside the cluster

```bash
# Get all node IPs
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}'

# Test each node individually
for NODE_IP in <node1-ip> <node2-ip> <node3-ip>; do
  echo -n "Node $NODE_IP: "
  curl -s --max-time 3 http://$NODE_IP:30080 || echo "FAILED"
done
# You will see some succeed and some fail
```

### Step 4 — Check the KUBE-NODEPORTS iptables rules

```bash
# On a node WITHOUT a backend pod:
kubectl debug node/<empty-node> -it --image=nicolaka/netshoot -- bash
  iptables -t nat -L KUBE-NODEPORTS -n | grep 30080
  # With Local policy: you will see a rule only matching local endpoints
  # If no local endpoints exist → traffic is simply dropped
```

---

## Log Analysis

```bash
# kube-proxy logs — look for endpoint sync errors
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=100 | grep -i error

# App logs — are connection refused errors logged?
kubectl logs -n shop deployment/backend --tail=50

# Events — look for probe failures
kubectl get events -n shop --sort-by='.lastTimestamp' | tail -20
```

---

## Common Causes

| # | Symptom | Cause | Signal |
|---|---------|-------|--------|
| 1 | Connection refused (ClusterIP) | `targetPort` != container port | Endpoints exist, curl to pod works directly |
| 2 | No endpoints | Selector labels mismatch | `kubectl get endpoints` shows `<none>` |
| 3 | NodePort works on some nodes | `externalTrafficPolicy: Local`, no pod on node | Different result per node |
| 4 | 502 from load balancer | Readiness probe failing | Pod Running but not Ready |
| 5 | DNS works but connection fails | Port name vs number mismatch | `curl` to ClusterIP fails, to pod IP works |
| 6 | Intermittent failures | One unhealthy endpoint in rotation | 1/3 requests fail consistently |

---

## Resolution

```bash
# Apply the fix
kubectl apply -f 03-solution.yaml

# Verify endpoints now show port 8080
kubectl describe svc backend-svc -n shop
# Look for: Endpoints: 10.x.x.x:8080,...

# Test internal connectivity
kubectl run test-curl --rm -it --restart=Never --image=curlimages/curl -- \
  curl http://backend-svc.shop.svc.cluster.local/
# Expected: Hello from backend

# Test NodePort from every node
kubectl get nodes -o wide
# Hit each node's IP on port 30080 — all should respond now
```

---

## Prevention

```bash
# 1. Always verify endpoints immediately after creating a service
kubectl get endpoints <svc-name> -n <namespace>

# 2. Use named ports in Deployments and reference by name in Services
#    This survives port changes without touching the Service:
# In Deployment:
#   ports:
#   - name: http        # <- name it
#     containerPort: 8080
# In Service:
#   targetPort: http    # <- reference by name, not number

# 3. Only use externalTrafficPolicy: Local when:
#    a) You NEED source IP preservation, AND
#    b) You use a DaemonSet (guaranteed 1 pod per node), OR
#    c) Your load balancer does health checks per node and skips empty ones

# 4. Add readiness probes to every container — this ensures endpoints
#    are only added when the app is actually ready to serve traffic
```

---

## Cleanup

```bash
kubectl delete namespace shop
```
