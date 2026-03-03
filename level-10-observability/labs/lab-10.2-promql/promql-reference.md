# Lab 10.2 — PromQL Reference: The 25 Queries Every K8s SRE Needs

Copy-paste these into your Prometheus or Grafana explore panel.
Each query is annotated with what it means and when to use it.

---

## Cluster Health

```promql
# 1. Nodes not Ready (should always be 0)
kube_node_status_condition{condition="Ready", status="true"} == 0

# 2. Nodes under memory pressure
kube_node_status_condition{condition="MemoryPressure", status="true"} == 1

# 3. Nodes under disk pressure
kube_node_status_condition{condition="DiskPressure", status="true"} == 1

# 4. Count of pods NOT in Running or Succeeded state (alert if > 0 sustained)
count(kube_pod_status_phase{phase!~"Running|Succeeded"}) by (phase, namespace)
```

---

## Pod and Container Health

```promql
# 5. Container restart rate — alert if any container restarts > 5 times in 1 hour
increase(kube_pod_container_status_restarts_total[1h]) > 5

# 6. Pods killed by OOMKiller in the last hour
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}

# 7. Pods not Ready (Running but readiness probe failing)
kube_pod_status_ready{condition="false"}

# 8. Containers with CPU throttling > 25% (causes latency even without CPU limit breach)
# Throttling happens when a container exceeds its CPU limit for a period
rate(container_cpu_cfs_throttled_seconds_total{container!=""}[5m]) /
  rate(container_cpu_cfs_periods_total{container!=""}[5m]) > 0.25

# 9. Container memory usage as % of limit (alert at 90%)
container_memory_working_set_bytes{container!=""}
  / on (pod, container, namespace)
  kube_pod_container_resource_limits{resource="memory", container!=""}
  > 0.90
```

---

## Resource Utilization

```promql
# 10. Node CPU utilization (1 = 100% used)
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# 11. Node memory utilization
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 12. Node disk utilization (alert at 80%)
1 - (node_filesystem_avail_bytes{mountpoint="/"} /
     node_filesystem_size_bytes{mountpoint="/"}) > 0.80

# 13. PVC disk usage (alert at 80%)
kubelet_volume_stats_used_bytes /
  kubelet_volume_stats_capacity_bytes > 0.80
```

---

## API Server Health

```promql
# 14. API server request latency P99 (> 1 second = degraded)
histogram_quantile(0.99,
  rate(apiserver_request_duration_seconds_bucket[5m])
) > 1

# 15. API server error rate (5xx errors)
rate(apiserver_request_total{code=~"5.."}[5m]) /
  rate(apiserver_request_total[5m]) > 0.01

# 16. etcd request latency P99 (> 100ms = etcd is slow)
histogram_quantile(0.99,
  rate(etcd_request_duration_seconds_bucket[5m])
) > 0.1

# 17. etcd leader changes (should be near 0 — frequent changes = cluster instability)
increase(etcd_server_leader_changes_seen_total[1h]) > 0
```

---

## Workload Health

```promql
# 18. Deployment replicas below desired (should always be 0 diff)
kube_deployment_status_replicas_available
  != kube_deployment_spec_replicas

# 19. StatefulSet replicas below desired
kube_statefulset_status_replicas_ready
  != kube_statefulset_status_replicas

# 20. HPA at maximum replicas (means it WANTS more but can't scale — capacity problem)
kube_horizontalpodautoscaler_status_current_replicas
  == kube_horizontalpodautoscaler_spec_max_replicas

# 21. Cluster Autoscaler failed to scale up
increase(cluster_autoscaler_failed_scale_ups_total[5m]) > 0
```

---

## Networking

```promql
# 22. Node network receive errors
rate(node_network_receive_errs_total[5m]) > 0

# 23. CoreDNS error rate (> 1% = DNS degraded)
rate(coredns_dns_responses_total{rcode="SERVFAIL"}[5m]) /
  rate(coredns_dns_responses_total[5m]) > 0.01

# 24. CoreDNS cache hit rate (< 70% = cache undersized or TTL too low)
rate(coredns_cache_hits_total[5m]) /
  rate(coredns_dns_requests_total[5m])
```

---

## Batch Jobs

```promql
# 25. Jobs that have failed
kube_job_status_failed > 0
```

---

## Useful PromQL Patterns for Debugging

```promql
# "Top 5 pods by CPU usage in a namespace"
topk(5, sum(rate(container_cpu_usage_seconds_total{namespace="production"}[5m]))
  by (pod))

# "Which pods have no resource limits set?"
count(kube_pod_container_info) by (pod, container, namespace)
  unless
count(kube_pod_container_resource_limits{resource="cpu"}) by (pod, container, namespace)

# "Memory growth trend — is this pod leaking memory?"
# (Rate of change of memory usage — positive and increasing = leak)
deriv(container_memory_working_set_bytes{pod="my-pod"}[30m])

# "What percentage of my pods are restartable?"
count(kube_pod_container_status_restarts_total > 0) /
  count(kube_pod_container_status_restarts_total)
```

---

## Alert Thresholds Reference

| Metric | Warning | Critical | Silence After |
|--------|---------|----------|---------------|
| Node not Ready | 1 node | 2+ nodes | N/A |
| Pod restarts | 3/hour | 10/hour | After fix deployed |
| CPU throttling | 25% | 50% | After limits adjusted |
| Memory near limit | 80% | 95% | After limits increased |
| Disk usage | 75% | 90% | After cleanup |
| API server p99 latency | 500ms | 2s | After root cause fixed |
| etcd leader changes | 1/hour | 3/hour | After etcd stabilized |

---

## Lab Exercise

Deploy the kube-prometheus-stack and explore each query:

```bash
# Install (requires Helm)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123

# Access Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090

# Access Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Login: admin / admin123
```

**Exercise:** For each query above, find it in Grafana's "Explore" panel,
run it, and explain in your own words what the graph is showing.
Then break something (kill a pod, fill a disk, generate CPU load) and
watch the metric react.
