# Lab 9.4 — etcd Disaster Recovery

## Scenario

Someone ran:
```bash
kubectl delete namespace production --grace-period=0 --force
```

All production workloads are gone. The most recent etcd snapshot is 2 hours old.
You have 30 minutes to restore before the SLA is breached.

**This runbook must be practiced on a disposable lab cluster.
Never practice a restore for the first time on a production system.**

---

## Prerequisites

```bash
# etcdctl must be installed and ETCDCTL_API=3 set
export ETCDCTL_API=3

# Find your etcd certificates (kubeadm cluster)
ETCD_CERT_FLAGS="
  --endpoints=https://127.0.0.1:2379
  --cacert=/etc/kubernetes/pki/etcd/ca.crt
  --cert=/etc/kubernetes/pki/etcd/server.crt
  --key=/etc/kubernetes/pki/etcd/server.key
"
```

---

## Step 1 — Take a Fresh Snapshot (Before the Disaster, as Practice)

```bash
# Run this on the control plane node (or via kubectl exec into the etcd pod)

# Via kubectl exec (safer — no need to SSH):
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  snapshot save /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).db

# Verify the snapshot
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl \
  snapshot status /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).db \
  --write-out=table

# Copy the snapshot off the control plane node
kubectl cp kube-system/etcd-$(hostname):/tmp/etcd-backup-latest.db ./etcd-backup-latest.db
```

---

## Step 2 — Simulate the Disaster

```bash
# Create test resources so we can verify restore worked
kubectl create namespace production
kubectl create deployment web --image=nginx --replicas=3 -n production
kubectl create configmap app-config --from-literal=env=production -n production

# Verify they exist
kubectl get all -n production

# NOW BREAK IT (the disaster)
kubectl delete namespace production --grace-period=0 --force

# Confirm deletion
kubectl get namespace production
# Error from server (NotFound): namespaces "production" not found
```

---

## Step 3 — Restore Procedure

### IMPORTANT: This stops the entire cluster briefly.
### Do NOT do this on a cluster serving live traffic without a maintenance window.

```bash
# SSH to the control plane node (you cannot use kubectl — apiserver will stop)

# 3a: Stop the kube-apiserver static pod
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
# Wait for apiserver to stop (kubelet detects manifest removal and stops the pod)
sleep 30
sudo crictl ps | grep apiserver  # Should show nothing

# 3b: Stop etcd
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml.bak
sleep 10
sudo crictl ps | grep etcd  # Should show nothing

# 3c: Back up the current (corrupted) etcd data
sudo mv /var/lib/etcd /var/lib/etcd-old

# 3d: Restore from snapshot
sudo etcdctl snapshot restore /path/to/etcd-backup.db \
  --data-dir=/var/lib/etcd \
  --initial-cluster="$(hostname)=https://127.0.0.1:2380" \
  --initial-cluster-token=etcd-cluster-restored \
  --initial-advertise-peer-urls=https://127.0.0.1:2380
# Note: use your actual hostname and control plane IPs for multi-node

# 3e: Fix ownership of the restored data
sudo chown -R etcd:etcd /var/lib/etcd
# OR if etcd runs as root:
# sudo chmod -R 700 /var/lib/etcd

# 3f: Update the etcd static pod manifest if needed
# The initial-cluster-token in the manifest must match what you used in restore
# Open /tmp/etcd.yaml.bak and check --initial-cluster-token
# If it doesn't match "etcd-cluster-restored", update the manifest

# 3g: Restore the static pod manifests (this starts etcd and apiserver)
sudo cp /tmp/etcd.yaml.bak /etc/kubernetes/manifests/etcd.yaml
sleep 20  # Wait for etcd to start
sudo cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
```

---

## Step 4 — Verify the Restore

```bash
# Wait 60-120 seconds for everything to start
watch kubectl get nodes

# Verify the restored namespace exists
kubectl get namespace production
# Expected: Active

# Verify restored workloads
kubectl get all -n production
# Expected: deployment.apps/web, pods, configmap

# Verify etcd is healthy
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  endpoint health
# Expected: https://127.0.0.1:2379 is healthy
```

---

## Step 5 — Post-Restore Checks

```bash
# Check all control plane components are healthy
kubectl get pods -n kube-system
# All should be Running or Completed

# Check nodes are Ready
kubectl get nodes

# Check controller manager is reconciling (will start recreating resources)
kubectl logs -n kube-system -l component=kube-controller-manager --tail=50

# Run a basic smoke test
kubectl run smoke-test --rm -it --restart=Never --image=alpine -- echo "cluster OK"
```

---

## Disaster Recovery Timing Reference

```
Action                                          Time
──────────────────────────────────────────────────────
Stop kube-apiserver (move manifest)             ~10-15s
Stop etcd (move manifest)                       ~10s
Restore snapshot (depends on db size)           ~30s-5min
Start etcd                                      ~20-30s
Start kube-apiserver                            ~30-60s
Cluster fully operational                       ~2-5 min total
```

---

## Log Analysis During Recovery

```bash
# Watch kubelet as it restarts static pods
sudo journalctl -u kubelet -f

# Watch etcd startup
sudo journalctl -u containerd -f | grep etcd

# Check etcd logs once it's running
kubectl logs -n kube-system etcd-$(hostname) --tail=50

# Common restore errors and fixes:
# "member ID from backup is different" → use --initial-cluster-token that matches manifest
# "permission denied" → fix ownership: chown -R etcd:etcd /var/lib/etcd
# "address already in use" → old etcd process still running: kill it first
```

---

## Common Causes of etcd Restore Situations

| Scenario | Recovery Approach |
|----------|-------------------|
| Accidental namespace/resource deletion | Restore from snapshot |
| etcd data corruption | Restore from snapshot to clean data-dir |
| etcd NOSPACE alarm (disk full) | Compact + defrag + clear alarm, or restore |
| Control plane VM destroyed | Rebuild node, then restore snapshot |
| Split brain (quorum loss) | Restore each member from same snapshot |

---

## etcd Maintenance Commands (Run Regularly)

```bash
# Compact old revisions (reclaim space without restore)
REVISION=$(kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  endpoint status --write-out=json | jq '.[0].Status.header.revision')

kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  compact $REVISION

# Defragment (reclaim disk space after compaction)
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  defrag

# Clear NOSPACE alarm (if disk was full, after freeing space)
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  alarm disarm

# Check current db size
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl $ETCD_CERT_FLAGS \
  endpoint status --write-out=table
```

---

## Backup Automation (Production Setup)

```bash
# CronJob to take etcd snapshots every 6 hours
# Save to a PVC backed by object storage (S3, GCS, Azure Blob)
# Keep 48 snapshots (12 days of recovery points at 6h intervals)
# Alert if backup is > 8 hours old

# Minimal backup script (run on control plane node or as a privileged CronJob)
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/backups/etcd"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT="${BACKUP_DIR}/etcd-${TIMESTAMP}.db"

etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "$SNAPSHOT"

etcdctl snapshot status "$SNAPSHOT" --write-out=table

# Delete backups older than 3 days
find "$BACKUP_DIR" -name "etcd-*.db" -mtime +3 -delete

echo "Backup complete: $SNAPSHOT"
```

---

## Prevention

```bash
# 1. Schedule automated etcd backups (minimum: every 6 hours for production)

# 2. Test restores quarterly — never assume backups work without testing them

# 3. Store backups in multiple locations (not on the control plane node disk)
#    S3 bucket, GCS, Azure Blob — outside the cluster

# 4. Monitor etcd db size and set alerts at 70% and 90% of quota
#    Default quota: 8GB
#    PromQL: etcd_mvcc_db_total_size_in_bytes / (8 * 1024 * 1024 * 1024) > 0.7

# 5. Monitor backup freshness:
#    Alert if last successful backup is > 8 hours old

# 6. Add RBAC protection — restrict who can delete namespaces in production:
kubectl create clusterrole namespace-delete-protection \
  --verb=delete \
  --resource=namespaces
# Then audit who has this ClusterRole
```
