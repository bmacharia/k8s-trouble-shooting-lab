# SRE Command Cheat Sheet

Quick reference for the most important Linux and Kubernetes troubleshooting commands.

---

## Linux SRE Commands — Top 50

### System Overview

```bash
uptime                             # Load + uptime
top / htop                         # Real-time monitoring
free -h                            # Memory
df -h / df -i                      # Disk space / inodes
iostat -xz 1                       # Disk I/O
mpstat -P ALL 1                    # Per-CPU stats
vmstat 1                           # CPU + memory + swap
dmesg -T | tail                    # Kernel messages
journalctl -p err --since "1h ago" # Recent errors
```

### Process

```bash
ps aux --sort=-%cpu | head         # Top CPU
ps aux --sort=-%mem | head         # Top memory
strace -p <PID> -c                 # System call profile
lsof -p <PID>                      # Open files
lsof -i :PORT                      # Port usage
pgrep -a <name>                    # Find process by name
kill <PID>                         # Graceful shutdown (SIGTERM)
kill -9 <PID>                      # Force kill (SIGKILL)
pkill -f "pattern"                 # Kill by command pattern
```

### Memory

```bash
free -h                            # Memory overview
cat /proc/meminfo                  # Detailed breakdown
vmstat -s                          # Memory stats
swapon --show                      # Swap devices
cat /proc/<PID>/status             # Process memory details
dmesg | grep -i oom                # OOM events
```

### Network

```bash
ss -tlnp                           # Listening ports
ss -tn state established           # Connections
ip addr / ip route                 # Interface + routing
dig +short <domain>                # DNS
curl -w "%{http_code} %{time_total}s\n" URL  # HTTP test
tcpdump -i eth0 port 80            # Packet capture
nc -zv host port                   # Port test
ping -c 4 host                     # Connectivity test
traceroute host                    # Path to destination
```

### Disk

```bash
du -sh /* | sort -rh               # Directory sizes
find / -size +100M -type f         # Large files
lsblk -f                           # Block devices
mount | column -t                  # Current mounts
cat /etc/fstab                     # Persistent mounts
fsck -n /dev/sda1                  # Filesystem check (dry run)
```

### Services & Logs

```bash
systemctl status <service>         # Service status
systemctl list-units --failed      # Failed services
systemctl restart <service>        # Restart service
journalctl -u <service> -f         # Follow service logs
journalctl --since "30 min ago"    # Recent logs
journalctl -p err                  # Errors only
```

### Users & Permissions

```bash
id                                 # Current user
namei -l /path/to/file             # Permissions along path
ls -la /path                       # File permissions
chmod 755 file                     # Set permissions
chown user:group file              # Change ownership
getfacl file                       # Extended ACLs
```

---

## Kubernetes SRE Commands — Top 50

### Cluster Health

```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
kubectl cluster-info
kubectl get componentstatuses
```

### Pod Troubleshooting

```bash
kubectl get pods -A --field-selector status.phase!=Running
kubectl describe pod <pod>
kubectl logs <pod> --previous --tail=100
kubectl logs <pod> -f
kubectl logs <pod> --since=1h
kubectl logs -l app=<label>
kubectl exec -it <pod> -- /bin/sh
kubectl debug -it <pod> --image=nicolaka/netshoot
kubectl get pod <pod> -o yaml
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'
```

### Service/Network

```bash
kubectl get svc,endpoints -n <ns>
kubectl describe svc <name>
kubectl run curl --rm -i --restart=Never --image=curlimages/curl -- curl <url>
kubectl run dns-test --rm -i --restart=Never --image=busybox -- nslookup <svc>
kubectl get networkpolicy -A
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Deployment Operations

```bash
kubectl rollout status deploy/<name>
kubectl rollout undo deploy/<name>
kubectl rollout restart deploy/<name>
kubectl rollout history deploy/<name>
kubectl scale deploy/<name> --replicas=N
kubectl set image deploy/<name> <container>=<image>
kubectl diff -f manifest.yaml
kubectl apply -f manifest.yaml --dry-run=server
```

### Resource Management

```bash
kubectl get resourcequota -A
kubectl describe namespace <ns>
kubectl get limitrange -A
kubectl auth can-i <verb> <resource> --as=<user>
kubectl get pvc -A
kubectl describe pvc <name>
kubectl get sc
```

### Node Operations

```bash
kubectl describe node <name>
kubectl drain <node> --ignore-daemonsets
kubectl uncordon <node>
kubectl cordon <node>
kubectl debug node/<name> -it --image=ubuntu
kubectl taint nodes <node> key=value:NoSchedule-
```

### Emergency

```bash
kubectl drain <node> --ignore-daemonsets
kubectl uncordon <node>
kubectl delete pod <pod> --force --grace-period=0
kubectl cordon <node>
kubectl rollout undo deploy/<name>
kubectl scale deploy/<name> --replicas=0
```

### Advanced Investigation

```bash
kubectl get pods -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName"
kubectl get deploy,rs,pods -l app=<label>
kubectl get all -n <namespace>
kubectl api-resources
kubectl get events --field-selector reason=Killing -A
```

---

*"The best SREs aren't the ones who never see outages — they're the ones who resolve them fastest and prevent them from happening again."*
