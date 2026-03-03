# Lab 6.5 — CoreDNS: Intermittent DNS Failures

## Symptoms

- External hostname resolution fails intermittently or consistently (`SERVFAIL`).
- Internal service discovery (`my-service.dns-lab.svc.cluster.local`) still works.
- The problem is worse under load (many DNS queries per second).
- Sometimes pods can't start because image pull fails on DNS lookup.

---

## Lab Setup

```bash
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-test-pods.yaml

# Apply the broken CoreDNS config (lab cluster only!)
kubectl apply -f 02-coredns-broken.yaml
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system

# Wait for pod to be Ready, then run tests
kubectl wait pod -n dns-lab dns-client --for=condition=Ready --timeout=60s
```

---

## How Kubernetes DNS Works

```
Pod issues DNS query
  │
  ▼
/etc/resolv.conf inside pod:
  nameserver 10.96.0.10         ← CoreDNS ClusterIP (kube-dns service)
  search dns-lab.svc.cluster.local svc.cluster.local cluster.local
  options ndots:5
  │
  ▼
CoreDNS pod receives query
  │
  ├── Is it a cluster name? (*.cluster.local)
  │     └── Answer from Kubernetes API (kubernetes plugin)
  │
  └── Is it external? (google.com)
        └── Forward to upstream (forward directive in Corefile)
              └── 8.8.8.8 or your configured resolver
```

**`ndots:5` means:** if the query has fewer than 5 dots, try appending each search domain first.
So `curl google.com` actually generates queries:
1. `google.com.dns-lab.svc.cluster.local` (fails, NXDOMAIN)
2. `google.com.svc.cluster.local` (fails)
3. `google.com.cluster.local` (fails)
4. `google.com.` (forwarded upstream — may fail if upstream is broken)

---

## Step 1 — Confirm DNS Failure Type

```bash
# Test internal DNS (Kubernetes service discovery)
kubectl exec -n dns-lab dns-client -- nslookup my-service.dns-lab.svc.cluster.local
# If this fails → CoreDNS itself is down or the kubernetes plugin is broken

# Test internal short-form (relies on search domains)
kubectl exec -n dns-lab dns-client -- nslookup my-service
# Same result as above for a pod in dns-lab namespace

# Test external DNS
kubectl exec -n dns-lab dns-client -- nslookup google.com
# If this fails but internal works → upstream forwarder is broken

# Test with explicit upstream to isolate
kubectl exec -n dns-lab dns-client -- nslookup google.com 8.8.8.8
# If THIS works → your CoreDNS upstream config is wrong (pointing to wrong IP)
```

---

## Step 2 — Check CoreDNS Pod Health

```bash
# Are CoreDNS pods running?
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Are they Ready?
kubectl get pods -n kube-system -l k8s-app=kube-dns \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'

# Describe for detailed health
kubectl describe pod -n kube-system -l k8s-app=kube-dns
```

---

## Step 3 — Read CoreDNS Logs

```bash
# This is the most informative source — read it carefully
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# Follow in real time while running a failing DNS lookup
kubectl logs -n kube-system -l k8s-app=kube-dns -f &
kubectl exec -n dns-lab dns-client -- nslookup google.com
# Kill the background log follow after
jobs && kill %1

# What to look for in logs:
# [ERROR] plugin/errors: 2 google.com. A: read udp: i/o timeout
#   → upstream not reachable (wrong IP, firewall, wrong port)
# [ERROR] plugin/errors: 2 google.com. A: SERVFAIL
#   → upstream returned an error
# [WARNING] plugin/loop: Loop detected
#   → forward is pointing back at CoreDNS itself
```

---

## Step 4 — Read the Corefile

```bash
# The Corefile is the ground truth for CoreDNS behavior
kubectl get configmap coredns -n kube-system -o yaml

# Focus on these lines:
# forward . <IP>    ← where external queries go — is this a valid DNS server?
# cache <seconds>   ← TTL for cached responses
# forward . /etc/resolv.conf  ← uses node's DNS (common in kubeadm clusters)

# Verify the upstream is actually reachable from a node
kubectl debug node/<any-node> -it --image=nicolaka/netshoot -- bash
  dig @10.0.0.1 google.com   # test the broken upstream directly
  dig @8.8.8.8 google.com    # test a known-good upstream
```

---

## Step 5 — Check the kube-dns Service

```bash
# CoreDNS pods must be reachable via the kube-dns service
kubectl get svc kube-dns -n kube-system

# Check endpoints — if empty, pods aren't matching the selector
kubectl get endpoints kube-dns -n kube-system

# Check what IP is configured in pods' resolv.conf
kubectl exec -n dns-lab dns-client -- cat /etc/resolv.conf
# nameserver should match the kube-dns ClusterIP
KUBEDNS_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "kube-dns ClusterIP: $KUBEDNS_IP"
```

---

## Step 6 — Measure DNS Latency (Performance Investigation)

```bash
# Time multiple DNS lookups to see latency
kubectl exec -n dns-lab dns-client -- bash -c '
  for i in $(seq 1 10); do
    start=$(date +%s%N)
    nslookup google.com > /dev/null 2>&1
    end=$(date +%s%N)
    echo "Query $i: $(( (end - start) / 1000000 ))ms"
  done
'

# Check CoreDNS metrics (if Prometheus is installed)
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl -s localhost:9153/metrics | grep -E "coredns_dns_request|coredns_forward|coredns_cache"
# Key metrics:
#   coredns_cache_hits_total         ← high = good (cache working)
#   coredns_forward_request_duration ← high = slow upstream
#   coredns_dns_requests_total       ← total query rate
kill %1
```

---

## Log Analysis Strategy

```bash
# Pattern 1: Upstream timeout
kubectl logs -n kube-system -l k8s-app=kube-dns | grep "i/o timeout"
# → Wrong upstream IP or upstream unreachable

# Pattern 2: NXDOMAIN flooding (ndots issue)
kubectl logs -n kube-system -l k8s-app=kube-dns | grep "NXDOMAIN" | wc -l
# → If very high, apps are generating too many search-domain queries
#   Fix: set ndots:2 in pod dnsConfig

# Pattern 3: Loop detected
kubectl logs -n kube-system -l k8s-app=kube-dns | grep -i loop
# → forward is pointing to CoreDNS itself (usually via /etc/resolv.conf on the node)

# Pattern 4: Truncated responses
kubectl logs -n kube-system -l k8s-app=kube-dns | grep -i truncat
# → UDP response too large, switch to TCP or reduce DNS answer size
```

---

## Common Causes

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | External DNS fails, internal works | Wrong upstream IP in `forward` | Fix Corefile `forward` directive |
| 2 | All DNS fails | CoreDNS pods down or not Ready | Restart pods, check OOM |
| 3 | Intermittent failures under load | Cache TTL too low | Increase `cache` seconds |
| 4 | DNS works then stops for 30s | CoreDNS loop detection triggered | Fix `forward` loop, check `loop` plugin |
| 5 | High latency on first requests | ndots:5 causing 4-5 failed lookups | Set `ndots: 2` in pod `dnsConfig` |
| 6 | NXDOMAIN for internal service | Wrong namespace or typo in hostname | Use FQDN: `svc.namespace.svc.cluster.local` |
| 7 | Pods can't start (image pull fails) | DNS broken → registry unreachable | Fix CoreDNS first |

---

## Resolution

```bash
# Apply the fixed Corefile
kubectl apply -f 03-solution.yaml

# Restart CoreDNS to pick up the change
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system

# Wait for pods to be Ready
kubectl wait pod -n kube-system -l k8s-app=kube-dns \
  --for=condition=Ready --timeout=60s

# Verify internal DNS
kubectl exec -n dns-lab dns-client -- nslookup my-service.dns-lab.svc.cluster.local
# Expected: Server: 10.96.0.10, Address resolved

# Verify external DNS
kubectl exec -n dns-lab dns-client -- nslookup google.com
# Expected: Name: google.com, Address resolved
```

---

## Optimization: Reduce ndots for Faster Lookups

```yaml
# Add this to pods that frequently query external hosts
# to avoid the 4 unnecessary search-domain queries:
spec:
  dnsConfig:
    options:
    - name: ndots
      value: "2"
  # With ndots:2, "google.com" (2 dots = >=ndots) is tried directly first
  # instead of trying all search domains first
```

---

## Prevention

```bash
# 1. Never change the CoreDNS ConfigMap without backing it up first:
kubectl get configmap coredns -n kube-system -o yaml > coredns-backup-$(date +%Y%m%d).yaml

# 2. Test Corefile syntax before applying (CoreDNS has a validator):
#    Install coredns binary locally and run:
coredns -conf /tmp/Corefile -validate

# 3. After any CoreDNS change, run the full DNS test matrix:
for target in "my-service.dns-lab.svc.cluster.local" "kubernetes.default.svc.cluster.local" "google.com"; do
  echo -n "Testing $target: "
  kubectl exec -n dns-lab dns-client -- nslookup $target > /dev/null 2>&1 \
    && echo "OK" || echo "FAILED"
done

# 4. Set CoreDNS PodDisruptionBudget to ensure at least 1 replica is always up:
kubectl get pdb -n kube-system | grep coredns
# If missing, create one:
kubectl create pdb coredns-pdb -n kube-system \
  --selector=k8s-app=kube-dns --min-available=1
```

---

## Cleanup

```bash
# Restore your original CoreDNS config before deleting the lab
kubectl apply -f 03-solution.yaml
kubectl rollout restart deployment/coredns -n kube-system
kubectl delete namespace dns-lab
```
