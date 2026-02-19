# Level 4: Kubernetes Advanced Operations

*"Advanced troubleshooting is about seeing the patterns others miss."*

**Time estimate: 25-30 hours**

---

## 4.1 etcd Troubleshooting

```bash
# etcd is the database of Kubernetes — if it's unhealthy, EVERYTHING is unhealthy

# ──────────────────────────────────────
# etcd Health Check
# ──────────────────────────────────────
# On a kubeadm cluster, etcd runs as a static pod:
kubectl get pods -n kube-system -l component=etcd

# Using etcdctl (may need to exec into etcd pod):
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check for alarms (e.g., NOSPACE)
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  alarm list

# ──────────────────────────────────────
# etcd Performance
# ──────────────────────────────────────
# Slow etcd = slow everything
# etcd needs fast disk I/O (SSD/NVMe recommended)

# Check etcd disk latency from metrics:
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

# ──────────────────────────────────────
# etcd Backup and Restore
# ──────────────────────────────────────
# BACKUP (do this regularly!)
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-out=table

# RESTORE (nuclear option — stops the cluster!)
# 1. Stop kube-apiserver and etcd
# 2. Restore:
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored
# 3. Point etcd config to new data-dir
# 4. Restart etcd and kube-apiserver
```

---

## 4.2 Certificate Troubleshooting

```bash
# Kubernetes uses TLS certificates EVERYWHERE
# Certificates expire and cause mysterious failures

# ──────────────────────────────────────
# Check Certificate Expiration
# ──────────────────────────────────────
# kubeadm clusters:
sudo kubeadm certs check-expiration

# Manual check:
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer

# Check all certs in /etc/kubernetes/pki:
for cert in /etc/kubernetes/pki/*.crt; do
  echo "=== $cert ==="
  openssl x509 -in $cert -noout -dates -subject 2>/dev/null
  echo ""
done

# ──────────────────────────────────────
# Renew Certificates
# ──────────────────────────────────────
# Renew all kubeadm certificates:
sudo kubeadm certs renew all

# After renewal, restart control plane components:
sudo systemctl restart kubelet
# Static pods (apiserver, controller-manager, scheduler) will restart automatically

# Update kubeconfig:
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
```

---

## 4.3 RBAC Troubleshooting

```bash
# ──────────────────────────────────────
# "Forbidden" errors = RBAC problem
# ──────────────────────────────────────

# Check what a user/service account can do:
kubectl auth can-i create pods --as=system:serviceaccount:default:myapp
kubectl auth can-i '*' '*' --as=system:serviceaccount:kube-system:admin  # Superuser check
kubectl auth can-i --list --as=system:serviceaccount:default:myapp       # List all permissions

# Find relevant roles/bindings:
kubectl get clusterroles | grep -i <keyword>
kubectl get clusterrolebindings | grep -i <keyword>
kubectl get roles -n <namespace>
kubectl get rolebindings -n <namespace>

# Describe a role to see what it allows:
kubectl describe clusterrole <role-name>
kubectl describe role <role-name> -n <namespace>

# Quick fix: Create a RoleBinding for a ServiceAccount
kubectl create rolebinding myapp-view \
  --clusterrole=view \
  --serviceaccount=default:myapp \
  -n <namespace>
```

---

## 4.4 Resource Quotas and Limits

```bash
# ──────────────────────────────────────
# When pods won't schedule due to quotas
# ──────────────────────────────────────
kubectl get resourcequota -A
kubectl describe resourcequota -n <namespace>

# LimitRange — default limits for pods
kubectl get limitrange -A
kubectl describe limitrange -n <namespace>

# Check a namespace's resource usage:
kubectl describe namespace <namespace>
# Shows quota usage vs limits

# Common fix: increase quota
kubectl patch resourcequota my-quota -n <namespace> \
  --type='json' -p='[{"op": "replace", "path": "/spec/hard/pods", "value": "100"}]'
```

---

## 4.5 Storage Troubleshooting

```bash
# ──────────────────────────────────────
# PVC Stuck in Pending
# ──────────────────────────────────────
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>

# Common reasons:
# 1. No matching PV (for static provisioning)
kubectl get pv

# 2. StorageClass doesn't exist
kubectl get sc
kubectl describe sc <storage-class-name>

# 3. Provisioner pod is not running
kubectl get pods -A | grep -i provisioner
kubectl get pods -A | grep -i csi

# 4. Volume binding mode is WaitForFirstConsumer
# PVC won't bind until a pod that uses it is scheduled

# ──────────────────────────────────────
# Volume Mount Issues
# ──────────────────────────────────────
kubectl describe pod <pod-name>
# Look for Events mentioning "MountVolume" or "FailedMount"

# Common issues:
# - PVC not found
# - Access mode mismatch (RWO on a shared volume)
# - Node can't access storage backend
# - fsGroup/security context issues
```

**Lab: [lab-4.1-fullstack-debug.yaml](labs/lab-4.1-fullstack-debug.yaml)** — Full-stack broken 3-tier app
