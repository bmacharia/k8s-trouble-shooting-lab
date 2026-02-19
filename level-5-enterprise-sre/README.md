# Level 5: Enterprise SRE Practices

*"An SRE's value isn't just fixing problems — it's preventing them."*

**Time estimate: 20-25 hours**

---

## 5.1 Incident Response Framework

### The OODA Loop for Incidents

```
┌──────────────────────────────────────────────────────┐
│              INCIDENT RESPONSE LOOP                   │
├──────────────────────────────────────────────────────┤
│                                                      │
│  1. OBSERVE                                          │
│     ├── What alerts fired?                           │
│     ├── What's the customer impact?                  │
│     ├── When did it start?                           │
│     └── What changed recently?                       │
│                                                      │
│  2. ORIENT                                           │
│     ├── Which component is affected?                 │
│     ├── Is it the app, infra, network, or external?  │
│     ├── Check dashboards, metrics, logs              │
│     └── Form a hypothesis                            │
│                                                      │
│  3. DECIDE                                           │
│     ├── Can we mitigate quickly? (rollback, scale)   │
│     ├── Do we need to escalate?                      │
│     ├── Is a hotfix possible?                        │
│     └── Choose the fastest path to recovery          │
│                                                      │
│  4. ACT                                              │
│     ├── Execute the fix                              │
│     ├── Verify the fix works                         │
│     ├── Monitor for recurrence                       │
│     └── Document everything in the incident channel  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**Script: [incident-runbook.sh](scripts/incident-runbook.sh)** — Quick response runbook

---

## 5.2 Monitoring and Alerting Stack

### Prometheus + Grafana on Kubernetes

```bash
# Install kube-prometheus-stack (Prometheus + Grafana + AlertManager)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi

# Access Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000 (admin/admin)

# Access Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

### Essential Prometheus Queries for SRE

```promql
# ──────────────────────────────────────
# Cluster Health
# ──────────────────────────────────────
# Node availability
kube_node_status_condition{condition="Ready",status="true"}

# Pod restart count (high restarts = instability)
increase(kube_pod_container_status_restarts_total[1h]) > 3

# Pods not running
kube_pod_status_phase{phase=~"Failed|Pending"} > 0

# ──────────────────────────────────────
# Resource Utilization
# ──────────────────────────────────────
# CPU utilization by node
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory utilization by node
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Pod CPU vs request
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)
/
sum(kube_pod_container_resource_requests{resource="cpu"}) by (pod)

# ──────────────────────────────────────
# SLI/SLO Queries
# ──────────────────────────────────────
# Request error rate (5xx)
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))

# P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Availability (uptime)
avg_over_time(up{job="myapp"}[24h])
```

**Manifest: [alert-rules.yaml](manifests/alert-rules.yaml)** — Essential Prometheus alert rules

---

## 5.3 SRE Best Practices Cheat Sheet

### Golden Rules

```
┌──────────────────────────────────────────────────────────────────┐
│                    SRE GOLDEN RULES                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. ALWAYS SET RESOURCE REQUESTS AND LIMITS                      │
│     - Prevents noisy neighbor problems                           │
│     - Enables accurate scheduling                                │
│     - Protects against OOM kills                                 │
│                                                                  │
│  2. ALWAYS USE HEALTH CHECKS                                     │
│     - Liveness probe: restart if stuck                           │
│     - Readiness probe: remove from service if not ready          │
│     - Startup probe: handle slow starts                          │
│                                                                  │
│  3. ALWAYS USE ROLLING UPDATES                                   │
│     - maxUnavailable: 25%  maxSurge: 25%                        │
│     - Set proper terminationGracePeriodSeconds                   │
│     - Use preStop hooks for graceful shutdown                    │
│                                                                  │
│  4. ALWAYS RUN MULTIPLE REPLICAS                                 │
│     - At least 2 replicas for any production service             │
│     - Use PodDisruptionBudget to survive maintenance             │
│     - Spread across nodes with topology constraints              │
│                                                                  │
│  5. ALWAYS HAVE OBSERVABILITY                                    │
│     - Metrics (Prometheus)                                       │
│     - Logs (centralized: EFK/Loki)                               │
│     - Traces (Jaeger/Tempo)                                      │
│     - Alerts (AlertManager)                                      │
│                                                                  │
│  6. ALWAYS BACKUP etcd                                           │
│     - Automated daily backups                                    │
│     - Test restores regularly                                    │
│     - Store backups off-cluster                                  │
│                                                                  │
│  7. ALWAYS USE NAMESPACES                                        │
│     - Separate environments (dev/staging/prod)                   │
│     - Resource quotas per namespace                              │
│     - RBAC per namespace                                         │
│                                                                  │
│  8. ALWAYS VERSION EVERYTHING                                    │
│     - GitOps: all manifests in Git                               │
│     - Never use :latest tag in production                        │
│     - Use image digests for immutability                         │
│                                                                  │
│  9. NEVER MODIFY RUNNING RESOURCES DIRECTLY                      │
│     - Change the YAML, apply the YAML                            │
│     - kubectl edit is for emergencies only                       │
│     - All changes should be auditable                            │
│                                                                  │
│  10. ALWAYS HAVE A ROLLBACK PLAN                                 │
│     - kubectl rollout undo deployment/<name>                     │
│     - Keep previous 5 ReplicaSet revisions                       │
│     - Feature flags over big-bang deployments                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Manifest: [production-deployment.yaml](manifests/production-deployment.yaml)** — Battle-tested deployment template

---

## 5.4 SRE Interview Preparation — Common Scenarios

### Scenario 1: "Our application is returning 502 errors"

```bash
# Systematic investigation:

# 1. WHERE are the 502s coming from?
# Is it the app, the ingress controller, or the load balancer?
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=100 | grep 502

# 2. Is the backend pod healthy?
kubectl get pods -l app=myapp
kubectl describe pod <pod> | grep -A 5 "Conditions"

# 3. Does the service have endpoints?
kubectl get endpoints myapp-service

# 4. Is the pod responding on its port?
kubectl exec -it <pod> -- curl -v http://localhost:8080/healthz

# 5. Check for resource exhaustion
kubectl top pods -l app=myapp
kubectl describe pod <pod> | grep -A 5 "Limits"

# 6. Check for network policies
kubectl get networkpolicy -n <namespace>

# Common root causes:
# - Pod is OOMKilled → increase memory limits
# - Readiness probe failing → pod removed from endpoints
# - Backend is slow → increase proxy timeouts
# - Connection refused → app didn't start properly
```

### Scenario 2: "Disk space is running out on a node"

```bash
# 1. Which mount point is full?
df -h

# 2. What's using the space?
du -sh /var/lib/* | sort -rh | head -10

# 3. Common culprits:
# Container images:
sudo crictl images | wc -l
sudo crictl rmi --prune     # Remove unused images

# Container logs (if not using journald):
find /var/log/containers -name "*.log" -size +100M

# Terminated pods' data:
sudo find /var/lib/kubelet/pods -type d | wc -l

# Old container layers:
sudo du -sh /var/lib/containerd

# 4. Emergency cleanup:
sudo crictl rmi --prune                              # Prune unused images
kubectl delete pods --field-selector status.phase=Failed -A  # Remove failed pods
sudo journalctl --vacuum-size=500M                   # Trim journal logs
```

### Scenario 3: "Pods can't reach external services"

```bash
# 1. Can pods resolve DNS?
kubectl run dns-test --rm -i --restart=Never --image=busybox -- nslookup google.com

# 2. Is CoreDNS healthy?
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# 3. Can pods reach the internet?
kubectl run net-test --rm -i --restart=Never --image=curlimages/curl -- curl -I https://google.com

# 4. Check node's external connectivity
# SSH to the node:
ping 8.8.8.8
curl -I https://google.com

# 5. Check iptables NAT rules (pod traffic should be masqueraded)
sudo iptables -t nat -L POSTROUTING -n -v

# 6. Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node --tail=20

# Common root causes:
# - DNS not working → CoreDNS pod issue
# - NAT not configured → iptables rules missing
# - Firewall blocking → check security groups / iptables INPUT
# - CNI plugin failure → check CNI pod logs
```

---

## 5.5 Continuous Learning Path

### Certifications to Pursue

```
┌──────────────────────────────────────────────────────────────────┐
│                   SRE CERTIFICATION PATH                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  LEVEL 1: Foundations                                            │
│  ├── Linux Foundation Certified System Administrator (LFCS)      │
│  ├── CompTIA Linux+                                              │
│  └── Red Hat Certified System Administrator (RHCSA)              │
│                                                                  │
│  LEVEL 2: Kubernetes                                             │
│  ├── Certified Kubernetes Administrator (CKA)        ← KEY CERT │
│  ├── Certified Kubernetes Application Developer (CKAD)           │
│  └── Certified Kubernetes Security Specialist (CKS)              │
│                                                                  │
│  LEVEL 3: Cloud + Specialization                                 │
│  ├── AWS Solutions Architect / SysOps Administrator              │
│  ├── GCP Professional Cloud DevOps Engineer                      │
│  ├── Azure Administrator Associate                               │
│  └── HashiCorp Certified: Terraform Associate                    │
│                                                                  │
│  LEVEL 4: SRE-Specific                                           │
│  ├── Google Cloud Professional Cloud Architect                   │
│  ├── Prometheus Certified Associate (PCA)                        │
│  └── Istio Certified Associate (ICA)                             │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Daily Practice Habits

```
┌──────────────────────────────────────────────────────────────────┐
│              DAILY SRE PRACTICE ROUTINE                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Morning (15 min):                                               │
│  ├── Break something in a lab cluster, then fix it               │
│  ├── Practice one kubectl troubleshooting scenario               │
│  └── Read one SRE blog post (Google SRE blog, Brendan Gregg)    │
│                                                                  │
│  Weekly (2-3 hours):                                             │
│  ├── Build a project: deploy an app end-to-end on k8s           │
│  ├── Practice CKA exam scenarios (killer.sh)                     │
│  ├── Write a runbook for a common incident                       │
│  └── Learn one new observability tool                            │
│                                                                  │
│  Monthly:                                                        │
│  ├── Conduct a chaos engineering exercise                        │
│  ├── Write a postmortem for a practice incident                  │
│  ├── Contribute to an open-source K8s project                    │
│  └── Practice a full incident response simulation                │
│                                                                  │
│  Essential Resources:                                            │
│  ├── Google SRE Book (free online): sre.google                   │
│  ├── Brendan Gregg's Performance Blog                            │
│  ├── killer.sh — CKA/CKAD exam simulator                         │
│  ├── KodeKloud — hands-on Kubernetes labs                        │
│  └── Kubernetes The Hard Way (Kelsey Hightower)                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
