# Kubernetes Expert Curriculum
## The Complete Path from Practitioner to Expert

*Designed by a Kubernetes production engineer with experience running clusters at scale.*

> **Philosophy:** Experts don't just know commands — they understand *why* things break,
> can form a hypothesis in under 60 seconds, and know which layer of the stack to look at first.
> Every lab here is built around a real production failure pattern I have seen or caused myself.

---

## Skill Tree Overview

```
BEGINNER                    INTERMEDIATE                 EXPERT
─────────────────────────────────────────────────────────────────────
Level 1: Linux Foundations  Level 3: K8s Core            Level 6: Networking Mastery
Level 2: Linux Deep Debug   Level 4: K8s Advanced        Level 7: Workloads & Scheduling
                            Level 5: Enterprise SRE      Level 8: Security Hardening
                                                         Level 9: Cluster Lifecycle
                                                         Level 10: Observability Stack
                                                         Level 11: Platform Engineering
                                                         Level 12: Production Simulation
```

---

## What the Existing Labs Cover (and what they miss)

| Level | Topic | Status | Gap |
|-------|-------|--------|-----|
| 1 | Linux Foundations | Complete | — |
| 2 | Linux Deep Troubleshooting | Complete | — |
| 3 | K8s Core (pods, services, nodes) | Basic | No CNI, no Ingress, no NetworkPolicy |
| 4 | K8s Advanced (etcd, RBAC, storage) | Basic | No cluster lifecycle, no admission |
| 5 | Enterprise SRE | Basic | No Prometheus hands-on, no chaos |

**Major gaps before you can call yourself an expert:**
- Container runtime debugging (crictl, containerd)
- Kubernetes networking internals (iptables, eBPF, CNI)
- Ingress, Gateway API, service mesh
- NetworkPolicy
- StatefulSets, Jobs, CronJobs at production scale
- Scheduling: affinity, topology spread, priority, PDB
- Autoscaling: HPA, VPA, KEDA
- Helm and Kustomize
- GitOps (ArgoCD)
- Operators and CRDs
- Admission controllers and webhooks
- Pod Security Standards
- Cluster upgrades and kubeadm
- Certificate rotation under pressure
- Disaster recovery (practice the restore, not just the backup)
- Performance tuning: API server, etcd, scheduler
- Observability: building dashboards, writing alert rules
- Chaos engineering

---

## Level 6: Kubernetes Networking Mastery

*"Most production incidents are networking problems in disguise."*

**Time estimate: 20-25 hours**

### Labs

#### Lab 6.1 — CNI Deep Dive: What Actually Routes Your Packets
**Scenario:** A pod can reach the internet but cannot reach another pod in a different namespace. No NetworkPolicy exists. The junior engineer says "it must be the app." It is not.

**Skills:**
- How CNI plugins wire up pod networking (veth pairs, bridges, overlays)
- Reading `ip route`, `ip link`, `iptables -t nat -L -n -v`
- Tracing a packet from Pod A → veth → bridge → overlay → Pod B
- Calico-specific: `calicoctl node status`, BGP peer state
- Cilium-specific: `cilium status`, `hubble observe`

**Experiments:**
```bash
# Map the network path manually
POD_A_IP=$(kubectl get pod pod-a -o jsonpath='{.status.podIP}')
NODE=$(kubectl get pod pod-a -o jsonpath='{.spec.nodeName}')

# On the node:
ip route get $POD_A_IP          # Which interface?
ip link show                     # See the veth pair
bridge link                      # Pod on which bridge?
iptables -t nat -L KUBE-SERVICES -n  # Service NAT rules
conntrack -L | grep $POD_A_IP   # Active connections
```

**Break-and-fix scenarios:**
1. Delete and recreate a CNI pod — watch pod networking recover
2. Corrupt iptables rules — observe and restore
3. IP pool exhaustion — what happens when CIDR is full
4. MTU mismatch causing packet drops in tunneled overlay

---

#### Lab 6.2 — Service Networking: From ClusterIP to ExternalTrafficPolicy
**Scenario:** External users get `connection reset` 5% of the time. The app logs show nothing. The service has 3 endpoints. One of them is a node that's being drained.

**Skills:**
- ClusterIP → iptables DNAT chain walkthrough
- NodePort vs LoadBalancer vs ExternalName
- `externalTrafficPolicy: Local` vs `Cluster` — when to use which
- Source IP preservation
- Session affinity
- kube-proxy modes: iptables vs IPVS

**Experiments:**
```bash
# Find the KUBE-SVC chain for a service
SERVICE_IP=$(kubectl get svc my-svc -o jsonpath='{.spec.clusterIP}')
iptables -t nat -L -n | grep $SERVICE_IP

# Check IPVS rules
ipvsadm -Ln

# Test externalTrafficPolicy impact
kubectl patch svc my-svc -p '{"spec":{"externalTrafficPolicy":"Local"}}'
# Hit from outside — some nodes now 404, explain why
```

---

#### Lab 6.3 — Ingress: Nginx, Certificates, and the Connection Chain
**Scenario:** HTTPS works. HTTP redirects to HTTPS. But for one specific path `/api/v1/upload`, large file uploads (>10MB) fail with 413. No one changed the app.

**Skills:**
- nginx-ingress controller internals
- Ingress annotations — the ones you actually need to know
- TLS termination and cert-manager
- `client_max_body_size`, proxy timeouts, connection draining
- Debugging via nginx controller pod logs
- Gateway API (the future of Ingress)

**Annotations reference for lab:**
```yaml
nginx.ingress.kubernetes.io/proxy-body-size: "0"          # unlimited
nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
nginx.ingress.kubernetes.io/enable-cors: "true"
nginx.ingress.kubernetes.io/rewrite-target: /
```

---

#### Lab 6.4 — NetworkPolicy: Zero-Trust in Practice
**Scenario:** You need to implement network segmentation. Frontend can reach backend. Backend can reach database. Nothing else. And nothing from outside the cluster should reach the database directly.

**Skills:**
- NetworkPolicy is additive (no policy = allow all; policy exists = deny all not matched)
- Ingress vs egress policy
- namespaceSelector vs podSelector
- Labeling namespaces for cross-namespace policy
- Testing with `kubectl exec` + `nc` / `curl`

**Lab manifests cover:**
1. Broken NetworkPolicy (too restrictive — breaks the app)
2. Broken NetworkPolicy (too permissive — allows lateral movement)
3. Fix both; verify with `nc` from restricted pods

---

#### Lab 6.5 — DNS Internals and CoreDNS Debugging
**Scenario:** Apps intermittently fail to resolve external hostnames. Internal resolution works. The issue is worse during peak traffic hours.

**Skills:**
- CoreDNS ConfigMap — understanding the Corefile
- ndots, search domains, negative caching
- DNS round-trip latency (`kubectl exec -- time nslookup ...`)
- CoreDNS metrics (cache hit rate, request rate)
- NodeLocal DNSCache — what it is and when to use it
- Common CoreDNS misconfigurations

**Experiments:**
```bash
# Check CoreDNS ConfigMap
kubectl get configmap -n kube-system coredns -o yaml

# Test resolution timing from inside a pod
kubectl run dns-bench --rm -it --image=alpine -- sh
time nslookup google.com          # External — goes upstream
time nslookup kubernetes.default   # Internal — cached

# Check CoreDNS metrics
kubectl port-forward -n kube-system svc/kube-dns 9153:9153
curl localhost:9153/metrics | grep coredns_dns_request
```

---

## Level 7: Workloads, Scheduling, and Autoscaling

*"Understanding workload types is what separates ops from platform engineers."*

**Time estimate: 20-25 hours**

### Labs

#### Lab 7.1 — StatefulSets: Ordered, Persistent, and Painful to Debug
**Scenario:** A 3-replica StatefulSet gets stuck at 1/3 ready. The second pod is in Pending. The third hasn't even been attempted. The PVC for pod-1 is stuck in Pending too.

**Skills:**
- StatefulSet ordering guarantees (pod-0 → pod-1 → pod-2)
- Stable network identity (`pod-0.my-service.namespace.svc.cluster.local`)
- PVC templates and per-pod storage
- Scaling StatefulSets safely
- Headless services
- StatefulSet update strategies (RollingUpdate, OnDelete)

**Break scenarios:**
1. PVC template using non-existent StorageClass
2. Wrong headless service selector
3. Pod-0 stuck in CrashLoopBackOff (blocks pod-1 from starting)
4. Scale down: what happens to PVCs?

---

#### Lab 7.2 — Jobs and CronJobs: Batch at Scale
**Scenario:** A nightly CronJob that processes user data is silently failing. No alerts fired because the job creates 0 pods (wrong schedule expression). Meanwhile, old completed jobs are accumulating and filling etcd.

**Skills:**
- Job completion modes: NonIndexed, Indexed, WorkQueue
- Job failure handling: `backoffLimit`, `restartPolicy`
- CronJob: schedule expressions, `concurrencyPolicy`, `startingDeadlineSeconds`
- `ttlSecondsAfterFinished` — why you must set this
- Suspending CronJobs during incidents
- Job parallelism

**Experiments:**
```bash
# Create a job that fails and observe backoff
kubectl create job fail-test --image=alpine -- /bin/false

# Watch the exponential backoff
kubectl get events --field-selector reason=BackoffLimitExceeded

# Check completed job cleanup
kubectl get jobs -A --sort-by=.metadata.creationTimestamp
```

---

#### Lab 7.3 — Scheduling: Affinity, Taints, and Topology Spread
**Scenario:** After adding a GPU node, all pods started scheduling on it. The GPU-hungry ML workload pods are getting evicted because regular pods took all the resources.

**Skills:**
- Node affinity vs node selector
- Pod affinity and anti-affinity (required vs preferred)
- Taints and tolerations (NoSchedule, PreferNoSchedule, NoExecute)
- Topology spread constraints — the right way to spread pods across AZs
- Priority classes — which pods survive when resources are tight
- Pod disruption budgets (PDB)

**Lab scenarios:**
```yaml
# Scenario 1: GPU node taint (restrict non-GPU workloads)
kubectl taint nodes gpu-node gpu=true:NoSchedule

# Scenario 2: Anti-affinity — spread replicas across zones
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: my-app

# Scenario 3: PDB — always keep 2/3 replicas during disruptions
kubectl create pdb my-pdb --selector=app=my-app --min-available=2
```

---

#### Lab 7.4 — HPA, VPA, and KEDA: Autoscaling in Practice
**Scenario:** The app scales up fine during load. But it never scales down — replicas stay at maximum all weekend. The team is paying for 10x more compute than needed.

**Skills:**
- HPA: CPU/memory triggers, custom metrics, behavior policies
- `scaleDown.stabilizationWindowSeconds` — why cooldown matters
- VPA: Off/Initial/Recreate/Auto modes
- HPA + VPA conflicts (never run both on the same deployment)
- KEDA: event-driven scaling (queue depth, Prometheus metric, cron)
- Cluster Autoscaler: when CA adds nodes vs HPA adds pods

**Experiments:**
```bash
# Install metrics-server (required for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA
kubectl autoscale deployment my-app --cpu-percent=50 --min=2 --max=20

# Watch scaling behavior under load
kubectl run load-gen --image=busybox -- /bin/sh -c \
  "while true; do wget -q -O- http://my-app; done"

# Check HPA state
kubectl get hpa my-app -w
kubectl describe hpa my-app   # Look at "Conditions" and "Events"
```

---

## Level 8: Security Hardening

*"In Kubernetes, the default answer to 'can this do X?' is often 'yes, unfortunately.'"*

**Time estimate: 20-25 hours**

### Labs

#### Lab 8.1 — RBAC Mastery: Least Privilege in Practice
**Scenario:** A developer's service account accidentally has cluster-admin because someone ran `kubectl create clusterrolebinding dev --clusterrole=cluster-admin --serviceaccount=default:default` during debugging and never cleaned it up.

**Skills:**
- Service accounts: what they are, how pods use them
- Roles vs ClusterRoles — namespace scope matters
- Aggregated ClusterRoles
- `kubectl auth can-i` — your RBAC Swiss Army knife
- `rbac-lookup` and `kubectl-who-can` for auditing
- Principle of least privilege in practice

**Audit exercise:**
```bash
# Find every subject with cluster-admin
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name=="cluster-admin") |
      {name: .metadata.name, subjects: .subjects}'

# Find all permissions for a service account
kubectl auth can-i --list --as=system:serviceaccount:default:my-sa

# Find who can do dangerous things
kubectl who-can create clusterrolebindings   # (requires plugin)
kubectl who-can delete secrets -A
```

---

#### Lab 8.2 — Pod Security Standards: Locking Down Workloads
**Scenario:** A security audit found that any developer can run privileged containers and mount the host filesystem. Anyone who can create a pod can escape to the node.

**Skills:**
- Pod Security Standards: Privileged / Baseline / Restricted
- Pod Security Admission (PSA) labels on namespaces
- Security context: runAsNonRoot, runAsUser, readOnlyRootFilesystem
- Dropping capabilities: `drop: [ALL]`
- seccomp profiles
- AppArmor annotations
- What a container escape looks like and why these settings matter

**Lab progression:**
```bash
# Label namespace with enforced Restricted policy
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

# Try to deploy a privileged container — it will be blocked
# Fix the deployment to meet Restricted policy
```

---

#### Lab 8.3 — Admission Controllers and Policy Engines
**Scenario:** A misconfigured deployment with `imagePullPolicy: Never` and a `latest` image tag made it to production and caused a 2-hour outage when nodes were replaced.

**Skills:**
- Admission webhook flow (ValidatingWebhookConfiguration, MutatingWebhookConfiguration)
- Kyverno: writing policies, ClusterPolicy, PolicyReport
- OPA/Gatekeeper: ConstraintTemplate, Constraint
- What to enforce: image tag policies, resource limits required, approved registries

**Kyverno policy example:**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-pod-resource-limits
spec:
  validationFailureAction: enforce
  rules:
  - name: check-container-resources
    match:
      resources:
        kinds: [Pod]
    validate:
      message: "Resource limits are required for all containers."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
```

---

#### Lab 8.4 — Secrets Management: Beyond the Default
**Scenario:** A secret containing a database password was base64-decoded from a git commit. The team was using `kubectl create secret` and committing the output YAML.

**Skills:**
- Why base64 is not encryption
- External Secrets Operator (ESO) + Vault / AWS Secrets Manager / GCP Secret Manager
- Sealed Secrets for GitOps
- Secret rotation: how to make pods pick up new secrets
- Encrypting secrets at rest in etcd

---

## Level 9: Cluster Lifecycle Management

*"Upgrading a cluster is not scary. Upgrading one you don't understand is."*

**Time estimate: 20-25 hours**

### Labs

#### Lab 9.1 — Building a kubeadm Cluster from Scratch
**Goal:** Build a 3-node HA cluster (1 control plane + 2 workers) with kubeadm, containerd, and Calico.

**Step-by-step:**
```bash
# Phase 1: Node preparation (all nodes)
# - Disable swap
# - Configure kernel modules (overlay, br_netfilter)
# - Install containerd
# - Install kubeadm, kubelet, kubectl

# Phase 2: Initialize control plane
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=k8s-api.example.com:6443 \
  --upload-certs

# Phase 3: Install CNI
kubectl apply -f calico.yaml

# Phase 4: Join workers
sudo kubeadm join k8s-api.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Phase 5: Verify
kubectl get nodes -o wide
kubectl get pods -A
```

---

#### Lab 9.2 — Cluster Upgrade: Zero Downtime
**Scenario:** The cluster is running 1.29. You need to upgrade to 1.30. There is active production traffic. Downtime is not acceptable.

**The upgrade sequence:**
```bash
# Step 1: Upgrade the control plane first
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=1.30.0-00
sudo kubeadm upgrade apply v1.30.0

# Step 2: Upgrade kubelet on control plane
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.30.0-00 kubectl=1.30.0-00
sudo systemctl restart kubelet

# Step 3: Drain and upgrade each worker
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
# SSH to worker-1:
sudo apt-get install -y kubeadm=1.30.0-00 kubelet=1.30.0-00
sudo kubeadm upgrade node
sudo systemctl restart kubelet
# Back on control plane:
kubectl uncordon worker-1

# Step 4: Verify
kubectl get nodes
```

**Break scenarios:**
1. Kubelet version skew (kubelet ahead of apiserver — blocked by validation)
2. CNI compatibility issue after upgrade
3. Admission webhook breaks with new API version

---

#### Lab 9.3 — Certificate Rotation Under Pressure
**Scenario:** It is 3am. The cluster is showing errors. kubectl returns `certificate has expired`. You have 15 minutes before the on-call engineer's SLA is breached.

**Skills:**
- kubeadm cert check-expiration
- Rotating all certs: `kubeadm certs renew all`
- Rotating individual certs
- Restarting static pods after cert rotation
- What happens to running workloads during cert rotation (nothing — data plane is unaffected)
- kubelet cert rotation (auto-renewal — make sure it is enabled)

**Prevention:**
```bash
# Set up a CronJob that checks cert expiry and alerts
# Check certs expiring in the next 30 days:
sudo kubeadm certs check-expiration | grep -v valid

# Automate renewal (add to crontab on control plane nodes):
# 0 2 1 * * /usr/bin/kubeadm certs renew all && systemctl restart kubelet
```

---

#### Lab 9.4 — etcd Disaster Recovery
**Scenario:** Someone ran `kubectl delete namespace production --grace-period=0 --force`. Everything is gone. The etcd backup is from 2 hours ago.

**Full restore procedure:**
```bash
# Step 1: Stop the API server (move static pod manifest)
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# Step 2: Stop etcd
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/

# Step 3: Restore from snapshot
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored \
  --initial-cluster="master=https://127.0.0.1:2380" \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://127.0.0.1:2380

# Step 4: Update etcd manifest to use restored data dir
sudo sed -i 's|/var/lib/etcd|/var/lib/etcd-restored|g' /tmp/etcd.yaml

# Step 5: Restore manifests
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Step 6: Wait and verify
kubectl get nodes
kubectl get pods -A
```

**This lab must be practiced on a disposable cluster before you need it in production.**

---

## Level 10: Observability Stack

*"You cannot fix what you cannot see. You cannot scale what you cannot measure."*

**Time estimate: 20-25 hours**

### Labs

#### Lab 10.1 — Build the Observability Stack from Scratch
**Goal:** Deploy Prometheus, Grafana, AlertManager, and Loki on a cluster — without using the Helm chart so you understand each component.

**Component by component:**
```bash
# 1. Prometheus (with ServiceMonitor discovery)
# 2. Node Exporter (DaemonSet — metrics from every node)
# 3. kube-state-metrics (Deployment — Kubernetes object metrics)
# 4. Grafana (Deployment + PVC + Ingress)
# 5. AlertManager (with PagerDuty/Slack routing)
# 6. Loki + Promtail (log aggregation)
```

---

#### Lab 10.2 — Writing PromQL That Actually Answers Questions
**The 20 queries every K8s SRE must know:**

```promql
# 1. Are nodes ready?
kube_node_status_condition{condition="Ready",status="true"} == 0

# 2. Pod restarts in the last hour (alert on > 5)
increase(kube_pod_container_status_restarts_total[1h]) > 5

# 3. OOMKilled pods
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}

# 4. Pods not ready
kube_pod_status_ready{condition="false"}

# 5. CPU throttling (> 25% = bad)
rate(container_cpu_cfs_throttled_seconds_total[5m]) /
rate(container_cpu_cfs_periods_total[5m]) > 0.25

# 6. Memory usage vs limit (> 90% = warning)
container_memory_working_set_bytes /
  on(pod,container) kube_pod_container_resource_limits{resource="memory"} > 0.90

# 7. PVC usage (alert before disk full)
kubelet_volume_stats_used_bytes /
  kubelet_volume_stats_capacity_bytes > 0.80

# 8. API server request latency (p99 > 1s = bad)
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m])) > 1

# 9. etcd leader changes (should be rare)
increase(etcd_server_leader_changes_seen_total[1h]) > 0

# 10. Deployment availability < desired
kube_deployment_status_replicas_available /
  kube_deployment_spec_replicas < 0.80

# 11. Node CPU saturation
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# 12. Cluster autoscaler failed to scale
cluster_autoscaler_failed_scale_ups_total > 0

# 13. HPA at max replicas (means it wants more but can't scale)
kube_horizontalpodautoscaler_status_current_replicas ==
  kube_horizontalpodautoscaler_spec_max_replicas

# 14. Job failures
kube_job_status_failed > 0

# 15. Certificate expiry (alert 30 days before)
apiserver_client_certificate_expiration_seconds{quantile="0.01"} < 2592000
```

---

#### Lab 10.3 — Alert Design: Signal vs Noise
**Scenario:** The team has 50 alerts. 40 of them fire every week and get ignored. 3 critical ones have never fired. One of those 3 was the one you needed last month.

**Framework for good alerts (Google SRE principles):**
1. Alert on **symptoms** (user impact), not causes
2. Every alert must have a runbook
3. P1 alerts wake people up — must be actionable in < 5 minutes
4. Use `for: 5m` — avoid flapping on transient spikes
5. Dead man's switch (alerting that fires if your alerting is broken)

**Alert categories to build:**
- SLO-based alerts (error rate > X% for Y minutes)
- Capacity alerts (headroom, not threshold)
- Control plane health
- Certificate expiry
- Backup freshness (is the backup job completing?)

---

#### Lab 10.4 — Distributed Tracing with OpenTelemetry
**Scenario:** A request takes 2.3 seconds end-to-end. The frontend team says it's the backend. The backend team says it's the database. You need proof.

**Skills:**
- OpenTelemetry Collector as a DaemonSet
- Jaeger or Tempo as trace backend
- Correlating traces with logs (trace ID in log fields)
- Finding the slow span
- P99 vs P50 — why the average lies

---

## Level 11: Platform Engineering

*"The best SRE is not the one who fixes the most incidents — it's the one who builds the systems where incidents don't happen."*

**Time estimate: 25-30 hours**

### Labs

#### Lab 11.1 — Helm Mastery: Beyond `helm install`
**Scenario:** You helm-installed a third-party chart. Now it needs customization that the chart doesn't support natively. A junior engineer wants to edit files in `~/.cache/helm`. You need a better approach.

**Skills:**
- Chart structure (templates, values, helpers, hooks, tests)
- `helm template` — render before you apply
- `helm diff` plugin — see what will change before upgrade
- `helm upgrade --atomic` — rollback on failure
- `helm rollback` — when things go wrong
- Values hierarchy: chart defaults → values.yaml → --set flags
- Writing your own chart
- Helm hooks (pre-install, post-install, pre-upgrade, pre-delete)
- Helm tests

**Debugging:**
```bash
# Render templates locally
helm template my-release ./my-chart -f values.yaml

# Dry run with server-side validation
helm install my-release ./my-chart --dry-run --debug

# See what an upgrade will change
helm diff upgrade my-release prometheus-community/kube-prometheus-stack

# Why is a release stuck in "pending-install"?
helm list -a                            # See all states including failed
kubectl get secrets -l owner=helm       # Helm stores state in secrets
helm history my-release                 # Full history with status
```

---

#### Lab 11.2 — GitOps with ArgoCD
**Scenario:** The team wants all cluster state to come from Git. Manual `kubectl apply` is banned. But there are 3 environments (dev, staging, prod) with different configs.

**Skills:**
- ArgoCD architecture (argocd-server, argocd-application-controller, repo-server, redis)
- Application CRD
- App of Apps pattern
- ApplicationSet for multi-cluster/multi-env
- Sync waves (ordering deployments)
- Resource hooks
- Kustomize overlays for per-environment config
- Secrets in GitOps (External Secrets Operator integration)
- Drift detection and auto-sync

**Architecture:**
```
Git Repository
├── base/
│   ├── deployment.yaml
│   └── service.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml    # replicas: 1
│   ├── staging/
│   │   └── kustomization.yaml     # replicas: 2
│   └── prod/
│       └── kustomization.yaml     # replicas: 5, HPA enabled
```

---

#### Lab 11.3 — Operators: Understanding and Debugging Custom Controllers
**Scenario:** The database operator pod is in CrashLoopBackOff. The database Custom Resource is stuck in "Provisioning" state. You have never seen this operator before.

**Skills:**
- How operators work (watch API, reconciliation loop)
- CRD structure and schema validation
- Inspecting operator logs and events
- Status conditions on custom resources
- Finalizers — why CRs get stuck in Terminating
- Building a simple operator with controller-runtime (bonus)

**Debugging approach:**
```bash
# Step 1: Check the CR status
kubectl get mydb -o yaml | grep -A 20 "status:"

# Step 2: Check operator logs
kubectl logs -n operators deployment/mydb-operator --tail=100

# Step 3: Check events
kubectl get events -n default --field-selector reason=Reconciliation

# Step 4: CR stuck in Terminating?
# Find the finalizer
kubectl get mydb my-database -o jsonpath='{.metadata.finalizers}'
# If the operator is dead, manually remove the finalizer
kubectl patch mydb my-database -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

#### Lab 11.4 — Multi-Tenancy: Namespace Isolation at Scale
**Scenario:** 10 teams share one cluster. Team A accidentally deleted Team B's ConfigMap because both use the same namespace. No quotas exist. One team ran a memory leak and affected everyone.

**Skills:**
- Namespace-per-team vs namespace-per-app vs cluster-per-team
- ResourceQuota and LimitRange per namespace
- NetworkPolicy for namespace isolation
- RBAC — one ClusterRole, per-namespace RoleBinding
- Hierarchical Namespace Controller (HNC)
- Cost allocation with kubecost labels

**Namespace template (apply to every team namespace):**
```yaml
# ResourceQuota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "100"
    services: "20"
    persistentvolumeclaims: "10"
---
# LimitRange (defaults for pods without limits)
apiVersion: v1
kind: LimitRange
metadata:
  name: team-defaults
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "4"
      memory: 8Gi
```

---

## Level 12: Production Simulation — The Expert Gauntlet

*"Under pressure, you fall to the level of your training, not your plans."*

**Time estimate: 20 hours (run repeatedly)**

> These labs have no instructions. You get a broken cluster, a symptom, and a timer.
> The first few times you will look things up. Eventually you will not need to.

### Scenario Bank

#### Gauntlet 1 — The Silent Failure
The cluster looks healthy. All pods are Running. But users are reporting 10% error rates.
- Hint: Not all Running pods are actually serving traffic.
- Skills: readiness probes, endpoints, load balancer health

#### Gauntlet 2 — The Cascading Failure
One microservice is slow. Then another. Then another. The whole application is down but every pod is Running.
- Hint: Timeouts without circuit breakers.
- Skills: NetworkPolicy, pod resource limits, dependency mapping

#### Gauntlet 3 — The Mystery OOM
Every night at 2am, 3 pods restart. No code was deployed. No traffic spike.
- Hint: Something happens at 2am on a schedule.
- Skills: CronJob investigation, memory leak detection, VPA analysis

#### Gauntlet 4 — The Node Plague
Pods keep being evicted from one specific node. The node shows Ready. Eviction events show DiskPressure but `df -h` shows 30% usage.
- Hint: Inodes vs disk space. Docker/containerd image layers.
- Skills: inode debugging, `crictl images`, `docker system df`

#### Gauntlet 5 — The Control Plane Meltdown
kubectl is slow. Queries take 15-30 seconds. Some return errors. No node is NotReady.
- Hint: etcd compaction has never been run. The database is fragmented.
- Skills: etcd performance, API server metrics, compaction

#### Gauntlet 6 — The Missing Traffic
A deployment was rolled out. Traffic to the new version is... 0. Old pods were deleted. New pods are Running. Users are hitting 502.
- Hint: The new deployment has a different label than the Service selector.
- Skills: Selector debugging, endpoint verification, rollout strategies

#### Gauntlet 7 — The Certificate Cliff
It is Monday morning. The cluster was working Friday. Now nothing works.
- Hint: Weekend + certificates expire on schedule.
- Skills: Cert expiry, kubeadm renew, static pod restart

#### Gauntlet 8 — The Runaway Workload
A CronJob that was supposed to run for 5 minutes has been running for 3 hours. It has consumed half the cluster's memory. It cannot be deleted — it is stuck in Terminating.
- Hint: Finalizers and a broken operator.
- Skills: Force termination, finalizer removal, resource cleanup

#### Gauntlet 9 — The RBAC Mystery
Developers can no longer deploy to their namespace. They had access yesterday. No one changed RBAC.
- Hint: A ClusterRoleBinding was accidentally deleted during unrelated cleanup.
- Skills: RBAC audit, kubectl auth can-i, RoleBinding reconstruction

#### Gauntlet 10 — The Storage Outage
A StatefulSet database pod crashed. It will not restart. The PVC exists and is Bound. The mount is failing.
- Hint: The node the pod scheduled on cannot reach the storage backend (NFS/Ceph/EBS).
- Skills: Node-level storage debugging, PV reclaim policies, pod rescheduling

---

## The Expert Mental Model

When you reach expert level, your first 60 seconds with any problem looks like this:

```
OBSERVE (0-15 seconds)
├── What is the user-visible symptom?
├── When did it start? (look at events timeline)
└── What changed recently? (deployments, configs, external)

ORIENT (15-30 seconds)
├── Which layer: App → K8s → Node → Network → Infrastructure?
├── Blast radius: is this one pod, one node, or the whole cluster?
└── kubectl get events --sort-by='.lastTimestamp' -A | tail -20

HYPOTHESIS (30-45 seconds)
├── Most likely cause based on symptom + layer
├── 2nd most likely cause
└── What single command would confirm/deny hypothesis 1?

ACT (45-60 seconds)
└── Run the confirming command — do not guess and apply fixes
```

**The experts who are most dangerous are the ones who skip the hypothesis step and go straight to applying fixes.**

---

## Recommended Practice Schedule

| Week | Focus | Labs |
|------|-------|------|
| 1-2 | Networking | 6.1, 6.2, 6.3, 6.4, 6.5 |
| 3-4 | Workloads | 7.1, 7.2, 7.3, 7.4 |
| 5-6 | Security | 8.1, 8.2, 8.3, 8.4 |
| 7-8 | Cluster Lifecycle | 9.1, 9.2, 9.3, 9.4 |
| 9-10 | Observability | 10.1, 10.2, 10.3, 10.4 |
| 11-12 | Platform Engineering | 11.1, 11.2, 11.3, 11.4 |
| 13-16 | Gauntlets (repeat) | 12.1-12.10 |

**Total additional time: ~130 hours on top of Levels 1-5**

---

## Tools to Master (Beyond kubectl)

```bash
# Cluster analysis
k9s                    # Terminal UI for Kubernetes
kubectl-neat           # Clean up kubectl output
kubectl-tree           # Show owner relationships
kubens / kubectx       # Fast namespace/context switching

# Networking
hubble                 # Cilium network observability
calicoctl              # Calico management
iptables / ipvsadm     # Low-level packet routing
tcpdump / wireshark    # Packet capture
netshoot               # The Swiss Army knife pod (nicolaka/netshoot)

# Debugging
crictl                 # Container runtime CLI (containerd, CRI-O)
kubectl-debug          # Ephemeral debug containers
stern                  # Multi-pod log tailing
kubectl-sniff          # Network packet capture from pods

# Helm
helm diff              # See upgrade changes before applying
helm secrets           # Encrypted secrets in Helm values
helm unittest          # Unit test your charts

# Security
kube-bench             # CIS benchmark checker
kube-hunter            # Penetration testing
trivy                  # Image and IaC security scanning
falco                  # Runtime security monitoring

# Cost
kubecost               # Cost allocation per namespace/team
goldilocks             # VPA recommendations for right-sizing
```

---

## How You Know You Are an Expert

You can answer these questions without searching:

1. A pod is in `Pending` — list the 6 most common causes in order of frequency.
2. A service has no endpoints — walk through the 4-step check.
3. etcd shows `NOSPACE` alarm — what is the immediate fix?
4. Certificate expired — what are the exact commands to recover?
5. Node is NotReady — what do you check first on the node itself?
6. A StatefulSet pod is stuck at `Init:0/1` — where do you look?
7. HPA is not scaling — what are the 3 things to check?
8. Traffic is going to old pods after a deployment — what is the most likely cause?
9. A pod was OOMKilled — how do you find the right memory limit to set?
10. etcd backup/restore — recite the procedure from memory.

If you can answer all 10 in under 2 minutes, you are ready for a senior K8s engineering role.
