# Level 2: Linux Deep Troubleshooting

*"The difference between a junior and senior SRE is systematic troubleshooting."*

**Time estimate: 20-25 hours**

---

## 2.1 The SRE Troubleshooting Methodology

### The USE Method (by Brendan Gregg)

For every resource, check **Utilization**, **Saturation**, and **Errors**.

```
┌──────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│ Resource     │ Utilization          │ Saturation           │ Errors               │
├──────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ CPU          │ mpstat, top (%CPU)   │ vmstat (run queue)   │ dmesg, perf          │
│ Memory       │ free -h, vmstat      │ vmstat (swapping)    │ dmesg (OOM kills)    │
│ Disk I/O     │ iostat, iotop        │ iostat (avgqu-sz)    │ dmesg, smartctl      │
│ Network      │ ip -s link, sar      │ ss (recv-Q, send-Q)  │ ip -s link (errors)  │
│ Storage Cap. │ df -h                │ df -i (inodes)       │ dmesg, fsck          │
└──────────────┴──────────────────────┴──────────────────────┴──────────────────────┘
```

### The RED Method (for Services)

For every service, check **Rate**, **Errors**, and **Duration**.

```
┌──────────────────────┬──────────────────────────────────────────┐
│ Metric               │ How to Check                             │
├──────────────────────┼──────────────────────────────────────────┤
│ Rate (requests/sec)  │ Access logs, metrics endpoint, ss count  │
│ Errors (error rate)  │ Error logs, HTTP 5xx count, curl tests   │
│ Duration (latency)   │ Response times, p99 latency, curl -w     │
└──────────────────────┴──────────────────────────────────────────┘
```

---

## 2.2 CPU Troubleshooting Deep Dive

```bash
# ──────────────────────────────────────
# CPU Utilization
# ──────────────────────────────────────
# Load average: 1-minute, 5-minute, 15-minute averages
uptime
cat /proc/loadavg

# Rule of thumb: load average > number of CPUs = overloaded
nproc                              # Number of CPUs

# Per-CPU utilization
mpstat -P ALL 1 5                  # All CPUs, 1s intervals, 5 times
mpstat 1                           # Overall, every second

# Key columns in mpstat:
# %usr  — User space CPU    (your applications)
# %sys  — Kernel space CPU  (system calls, I/O)
# %iowait — Waiting for I/O (disk/network bottleneck)
# %steal — Stolen by hypervisor (VM/cloud issue!)
# %idle  — Unused CPU

# ──────────────────────────────────────
# CPU Saturation
# ──────────────────────────────────────
vmstat 1 5                         # Virtual memory stats
# Key columns:
# r = run queue (processes waiting for CPU)
# b = blocked (processes waiting for I/O)
# If 'r' > number of CPUs → CPU saturation

# ──────────────────────────────────────
# CPU - Who's Using It?
# ──────────────────────────────────────
top -b -n 1 -o %CPU | head -20    # Top CPU consumers
pidstat 1 5                        # Per-process CPU usage
pidstat -t 1 5                     # Per-thread CPU usage

# ──────────────────────────────────────
# CPU Profiling (Advanced)
# ──────────────────────────────────────
# strace — see what system calls a process makes
strace -p <PID> -c                # System call summary
strace -p <PID> -e trace=network  # Only network calls
strace -p <PID> -e trace=file     # Only file operations
strace -tt -p <PID>               # With timestamps

# perf — CPU profiling
sudo perf top                     # Real-time CPU profiling
sudo perf record -p <PID> -g -- sleep 10  # Record for 10s
sudo perf report                  # View the profile
```

---

## 2.3 Memory Troubleshooting Deep Dive

```bash
# ──────────────────────────────────────
# Memory Overview
# ──────────────────────────────────────
free -h                            # Memory summary
# Key fields:
# total    — Total physical RAM
# used     — Used (excluding buffers/cache)
# free     — Completely unused
# buff/cache — Disk cache (reclaimable!)
# available — Actually available for applications

# CRITICAL: "free" near 0 is NORMAL on Linux!
# Linux uses free RAM for disk caching.
# Look at "available" instead.

# ──────────────────────────────────────
# Detailed Memory
# ──────────────────────────────────────
cat /proc/meminfo                  # Detailed memory breakdown
vmstat -s                          # Memory statistics
vmstat 1 5                         # Memory + CPU over time
# Key columns:
# si = swap in (reading from swap — BAD if high)
# so = swap out (writing to swap — BAD if high)
# If si/so > 0 frequently → memory pressure

# ──────────────────────────────────────
# Per-Process Memory
# ──────────────────────────────────────
ps aux --sort=-%mem | head -20    # Top memory consumers
# Key columns:
# %MEM — percentage of total RAM
# RSS  — Resident Set Size (actual physical memory used)
# VSZ  — Virtual memory size (includes shared, mapped, unused)

# Detailed process memory
cat /proc/<PID>/status | grep -E "^(VmSize|VmRSS|VmSwap|RssAnon|RssFile)"
# VmRSS = actual memory in RAM
# VmSwap = memory pushed to swap
# RssAnon = heap + stack (real app usage)
# RssFile = file-backed memory (shared libraries)

pmap -x <PID> | tail -5           # Process memory map summary
smem -t -k                        # Proportional memory accounting (install: apt install smem)

# ──────────────────────────────────────
# OOM Killer Investigation
# ──────────────────────────────────────
# The OOM killer activates when the system runs out of memory
dmesg | grep -i "oom\|out of memory\|killed process"
journalctl -k | grep -i oom       # Kernel messages about OOM
grep -i "oom" /var/log/syslog     # Syslog OOM entries

# OOM score: higher = more likely to be killed
cat /proc/<PID>/oom_score          # Current OOM score
cat /proc/<PID>/oom_score_adj      # Adjustment (-1000 to 1000)

# Protect a critical process from OOM killer:
echo -1000 | sudo tee /proc/<PID>/oom_score_adj

# ──────────────────────────────────────
# Swap Analysis
# ──────────────────────────────────────
swapon --show                      # Active swap devices
cat /proc/swaps                    # Same info from proc

# Which processes are using swap?
for pid in /proc/[0-9]*; do
  swap=$(grep VmSwap $pid/status 2>/dev/null | awk '{print $2}')
  if [ -n "$swap" ] && [ "$swap" -gt 0 ]; then
    comm=$(cat $pid/comm 2>/dev/null)
    echo "$swap kB - PID $(basename $pid) - $comm"
  fi
done | sort -rn | head -10
```

**Lab: [lab-2.1-memory-pressure.sh](labs/lab-2.1-memory-pressure.sh)**

---

## 2.4 Disk I/O Troubleshooting

```bash
# ──────────────────────────────────────
# I/O Monitoring
# ──────────────────────────────────────
iostat -xz 1 5                     # Extended disk stats
# Key columns:
# %util   — How busy the device is (100% = saturated)
# r/s, w/s — Reads/writes per second
# avgqu-sz — Average queue length (saturation indicator)
# await   — Average I/O wait time (ms)
# r_await, w_await — Read/write latency separately

# ──────────────────────────────────────
# Per-Process I/O
# ──────────────────────────────────────
sudo iotop -o                      # Show only processes doing I/O
sudo iotop -b -n 5                 # Batch mode, 5 iterations
pidstat -d 1 5                     # Per-process disk I/O

# ──────────────────────────────────────
# Find I/O-Heavy Processes
# ──────────────────────────────────────
# Check /proc for I/O stats per process
cat /proc/<PID>/io
# read_bytes: total bytes read from disk
# write_bytes: total bytes written to disk

# One-liner to find top I/O processes:
for pid in /proc/[0-9]*; do
  if [ -f "$pid/io" ]; then
    wb=$(grep write_bytes $pid/io 2>/dev/null | awk '{print $2}')
    rb=$(grep read_bytes $pid/io 2>/dev/null | awk '{print $2}')
    comm=$(cat $pid/comm 2>/dev/null)
    echo "$wb $rb $(basename $pid) $comm"
  fi
done 2>/dev/null | sort -rn | head -10

# ──────────────────────────────────────
# Disk Health
# ──────────────────────────────────────
sudo smartctl -a /dev/sda          # SMART health data
sudo smartctl -H /dev/sda          # Quick health check
dmesg | grep -i -E "error|fail|sda|disk"  # Disk errors in kernel log
```

---

## 2.5 Network Deep Troubleshooting

```bash
# ──────────────────────────────────────
# Packet Capture (tcpdump)
# ──────────────────────────────────────
sudo tcpdump -i eth0 -n            # All traffic on eth0
sudo tcpdump -i any port 80        # HTTP traffic on all interfaces
sudo tcpdump -i eth0 host 10.0.0.5 # Traffic to/from specific host
sudo tcpdump -i eth0 -A port 80    # Show packet content (ASCII)
sudo tcpdump -i eth0 -w capture.pcap  # Save to file for Wireshark
sudo tcpdump -i eth0 -c 100        # Capture only 100 packets
sudo tcpdump -i eth0 'tcp[tcpflags] & tcp-syn != 0'  # SYN packets only

# ──────────────────────────────────────
# Network Performance
# ──────────────────────────────────────
# Bandwidth test
iperf3 -s                          # Start server
iperf3 -c <server_ip>              # Run client test

# Interface statistics
ip -s link show eth0               # Packets, bytes, errors, drops
cat /proc/net/dev                  # All interface statistics

# ──────────────────────────────────────
# Connection Debugging
# ──────────────────────────────────────
# TCP connection states
ss -tn | awk '{print $1}' | sort | uniq -c | sort -rn
# HIGH TIME_WAIT → many short-lived connections
# HIGH CLOSE_WAIT → application not closing connections
# HIGH ESTABLISHED → normal or connection leak

# Per-connection details
ss -tnp | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn
# Shows which IPs have most connections

# ──────────────────────────────────────
# Network Namespace (for containers)
# ──────────────────────────────────────
sudo lsns -t net                   # List network namespaces
sudo nsenter -t <PID> -n ip addr   # Enter a container's network namespace
sudo nsenter -t <PID> -n ss -tlnp  # See ports inside a container
```

---

## 2.6 The /proc and /sys Filesystems — Your Diagnostic Goldmine

```bash
# ──────────────────────────────────────
# /proc — Process and Kernel Information
# ──────────────────────────────────────
cat /proc/cpuinfo                  # CPU details
cat /proc/meminfo                  # Memory details
cat /proc/loadavg                  # Load averages + runnable processes
cat /proc/uptime                   # System uptime in seconds
cat /proc/version                  # Kernel version
cat /proc/filesystems              # Supported filesystems
cat /proc/mounts                   # Current mounts
cat /proc/net/tcp                  # TCP connections (hex)
cat /proc/net/sockstat             # Socket statistics summary
cat /proc/vmstat                   # Virtual memory statistics
cat /proc/diskstats                # Disk I/O statistics

# Sysctl (kernel tunables)
sysctl -a                          # All kernel parameters
sysctl vm.swappiness               # Swap tendency (0-100)
sysctl net.core.somaxconn          # Max connection backlog
sysctl net.ipv4.tcp_max_syn_backlog  # SYN backlog

# ──────────────────────────────────────
# Common SRE Sysctl Tuning
# ──────────────────────────────────────
# Reduce swap aggressiveness
sudo sysctl -w vm.swappiness=10

# Increase connection tracking
sudo sysctl -w net.core.somaxconn=65535
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=65535

# Enable TCP reuse (important for high-traffic servers)
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

# Increase file descriptor limits
sudo sysctl -w fs.file-max=2097152

# Make permanent:
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.d/99-sre.conf
sudo sysctl -p /etc/sysctl.d/99-sre.conf
```

**Lab: [lab-2.2-system-diagnostic.sh](labs/lab-2.2-system-diagnostic.sh)** — Full SRE diagnostic report script
