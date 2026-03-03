# Gauntlet 4 — The Node Plague: DiskPressure with Available Disk

## Symptom

```
kubectl describe node worker-01
Conditions:
  DiskPressure    True    KubeletHasDiskPressure

kubectl get events -A | grep Evict
# Pods being evicted from worker-01
```

But:
```bash
# SSH to worker-01
df -h /var/lib/containerd
# Filesystem: 50G, Used: 15G (30% used) — plenty of disk!
```

The junior engineer checks disk: "30% used, disk is fine."
Goes to lunch. Evictions continue.

---

## The Investigation

### Step 1 — Check INODES, not just bytes

```bash
# On the node
df -i /var/lib/containerd
# Filesystem  Inodes  IUsed  IFree  IUse%  Mounted on
# /dev/sda1   655360  655359 1      100%   /

# IUse% = 100% → inode exhaustion
# Every file in the OS takes one inode regardless of file size.
# Thousands of 1-byte files = thousands of inodes consumed.

# Find which directory has the most inodes used
find /var/lib/containerd -maxdepth 2 -type d | while read dir; do
  count=$(find "$dir" -maxdepth 1 -type f | wc -l)
  echo "$count $dir"
done | sort -rn | head -20

# Check container logs accumulation
find /var/log/containers -name "*.log" | wc -l
du -sh /var/log/containers
```

### Step 2 — Free the inodes

```bash
# Remove unused container images (biggest win)
sudo crictl rmi --prune

# Check how many images you have
sudo crictl images | wc -l

# Remove stopped/exited containers
sudo crictl rm $(sudo crictl ps -a -q --state exited)

# Rotate large log files
sudo find /var/log/containers -name "*.log" -size +100M
sudo truncate -s 0 /var/log/containers/<large-log-file>

# Re-check inodes
df -i /var/lib/containerd
```

### Step 3 — Wait for kubelet to clear the DiskPressure condition

```bash
# Kubelet checks conditions every 10 seconds
# After inodes are freed, DiskPressure will clear

# Watch the node condition
watch kubectl describe node worker-01 | grep DiskPressure
# Should change from True to False within 60 seconds

# Uncordon the node if it was cordoned during evictions
kubectl uncordon worker-01
```

---

## Prevention

```bash
# 1. Set log rotation on every node via kubelet config:
# /var/lib/kubelet/config.yaml:
#   containerLogMaxSize: 50Mi
#   containerLogMaxFiles: 3

# 2. Alert on inode usage — add to node_exporter monitoring:
node_filesystem_files_free{mountpoint="/"} /
  node_filesystem_files{mountpoint="/"} < 0.10

# 3. Run image GC regularly — kubelet does this automatically but configure it:
# imageGCHighThresholdPercent: 85  (start GC at 85% disk)
# imageGCLowThresholdPercent: 80   (GC until 80% disk)

# 4. Monitor the number of images on nodes:
# ssh to each node:
sudo crictl images | wc -l
# Alert if > 50 images on a node
```
