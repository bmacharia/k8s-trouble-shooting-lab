# Level 9: Cluster Lifecycle Management

*"Upgrading a cluster is not scary. Upgrading one you don't understand is."*

**Time estimate: 20-25 hours**

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [9.1 kubeadm Build](labs/lab-9.1-kubeadm-build/) | Build a 3-node cluster from scratch | containerd, kubeadm init/join, CNI install |
| [9.2 Upgrade](labs/lab-9.2-upgrade/) | Upgrade 1.29 → 1.30 with zero downtime | kubeadm upgrade, drain/uncordon, version skew |
| [9.3 Cert Rotation](labs/lab-9.3-cert-rotation/) | Cert expired at 3am | kubeadm certs renew, static pod restart, kubelet cert rotation |
| [9.4 etcd DR](labs/lab-9.4-etcd-dr/) | Namespace deleted, restore from backup | snapshot save/restore, compaction, defrag |

---

## Key Rules for Cluster Lifecycle

```
1. Never upgrade more than one minor version at a time (1.28 → 1.29 → 1.30, not 1.28 → 1.30)
2. Always upgrade the control plane before workers
3. Kubelet version must not be newer than apiserver version
4. Always take an etcd snapshot before upgrading
5. Test restores quarterly — a backup is only as good as the last successful restore
```
