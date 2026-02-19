#!/bin/bash
# ================================================================
# SRE System Diagnostic Report
# Run this when investigating any production issue
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
echo "CPUs:     $(nproc)"
echo ""

echo "═══ 2. CPU ═══"
echo "Load Average: $(cat /proc/loadavg)"
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
echo "Swap usage by process:"
for pid in /proc/[0-9]*; do
  swap=$(grep VmSwap $pid/status 2>/dev/null | awk '{print $2}')
  if [ -n "$swap" ] && [ "$swap" -gt 1000 ]; then
    comm=$(cat $pid/comm 2>/dev/null)
    echo "  $swap kB - $(basename $pid) - $comm"
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
systemctl --failed
echo ""

echo "═══ 7. RECENT ERRORS (last 30 min) ═══"
journalctl --since "30 min ago" -p err --no-pager | tail -20
echo ""

echo "═══ 8. OOM EVENTS ═══"
dmesg | grep -i "oom\|killed process" | tail -5
echo ""

echo "═══ 9. DISK I/O ═══"
iostat -xz 1 1 2>/dev/null || echo "iostat not installed (apt install sysstat)"
echo ""

echo "═══ DIAGNOSTIC COMPLETE ═══"
