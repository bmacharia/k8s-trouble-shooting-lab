#!/bin/bash
# ================================================================
# SRE System Diagnostic Report — Standalone Version
#
# Run this on any Linux system to get a full health report.
# Usage: ./sre-diagnostic-report.sh
# Usage: ./sre-diagnostic-report.sh > report.txt 2>&1
# ================================================================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           SRE SYSTEM DIAGNOSTIC REPORT                  ║"
echo "║           $(date)                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "═══ 1. SYSTEM OVERVIEW ═══"
echo "Hostname: $(hostname)"
echo "Uptime:   $(uptime)"
echo "Kernel:   $(uname -r)"
echo "OS:       $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "CPUs:     $(nproc)"
echo "Arch:     $(uname -m)"
echo ""

echo "═══ 2. CPU ═══"
echo "Load Average: $(cat /proc/loadavg)"
echo "CPU Count:    $(nproc)"
LOAD=$(cat /proc/loadavg | awk '{print $1}')
CPUS=$(nproc)
echo "Status:       $(echo "$LOAD $CPUS" | awk '{if ($1 > $2) print "OVERLOADED (load > CPU count)"; else print "OK"}')"
echo ""
echo "Top 5 CPU consumers:"
ps aux --sort=-%cpu | head -6
echo ""

echo "═══ 3. MEMORY ═══"
free -h
echo ""
echo "Top 5 Memory consumers:"
ps aux --sort=-%mem | head -6
echo ""
echo "Swap usage by process (>1MB):"
for pid in /proc/[0-9]*; do
  swap=$(grep VmSwap "$pid/status" 2>/dev/null | awk '{print $2}')
  if [ -n "$swap" ] && [ "$swap" -gt 1000 ]; then
    comm=$(cat "$pid/comm" 2>/dev/null)
    echo "  $swap kB - $(basename "$pid") - $comm"
  fi
done | sort -rn | head -5
echo ""

echo "═══ 4. DISK ═══"
echo "Filesystem usage:"
df -hT | grep -v tmpfs
echo ""
echo "Inode usage (>50%):"
df -i | awk 'NR>1 && $5+0 > 50 {print $0}'
echo ""

echo "═══ 5. NETWORK ═══"
echo "Listening ports:"
ss -tlnp 2>/dev/null | head -20
echo ""
echo "Connection states:"
ss -tn | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
echo ""

echo "═══ 6. FAILED SERVICES ═══"
systemctl --failed 2>/dev/null || echo "(systemctl not available)"
echo ""

echo "═══ 7. RECENT ERRORS (last 30 min) ═══"
journalctl --since "30 min ago" -p err --no-pager 2>/dev/null | tail -20 || echo "(journalctl not available)"
echo ""

echo "═══ 8. OOM EVENTS ═══"
dmesg 2>/dev/null | grep -i "oom\|killed process" | tail -5 || echo "(dmesg not available)"
echo ""

echo "═══ 9. DISK I/O ═══"
iostat -xz 1 1 2>/dev/null || echo "iostat not installed (apt install sysstat)"
echo ""

echo "═══ 10. KUBERNETES (if available) ═══"
if command -v kubectl &>/dev/null; then
  echo "Nodes:"
  kubectl get nodes 2>/dev/null || echo "  Cannot connect to cluster"
  echo ""
  echo "Non-running pods:"
  kubectl get pods -A --field-selector status.phase!=Running 2>/dev/null | head -10 || true
else
  echo "kubectl not found — skipping Kubernetes checks"
fi
echo ""

echo "═══ DIAGNOSTIC COMPLETE ═══"
echo "Report generated at: $(date)"
