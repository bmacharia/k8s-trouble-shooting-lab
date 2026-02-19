#!/bin/bash
# ================================================================
# Lab 1.4: Process Investigation
# Level 1 - Linux Foundations for SRE
# Lab: Hunt and Kill a Runaway Process
# ================================================================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        Lab 1.4: Process Investigation                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Create a CPU-hungry process
echo "═══ Step 1: Creating CPU-hungry processes ═══"
cat <<'EOF' > /tmp/cpu_hog.sh
#!/bin/bash
while true; do
  echo "scale=10000; 4*a(1)" | bc -l > /dev/null 2>&1
done
EOF
chmod +x /tmp/cpu_hog.sh

# Start 3 instances in background
/tmp/cpu_hog.sh &
/tmp/cpu_hog.sh &
/tmp/cpu_hog.sh &
echo "Started 3 CPU hog processes."
echo ""

# Step 2: Create a memory-hungry process
echo "═══ Step 2: Creating memory-hungry process ═══"
cat <<'EOF' > /tmp/mem_hog.py
#!/usr/bin/env python3
import time
data = []
while True:
    data.append('x' * 1024 * 1024)  # Add 1MB each iteration
    time.sleep(0.5)
    if len(data) > 200:  # Cap at ~200MB
        data = data[-200:]
    time.sleep(1)
EOF
python3 /tmp/mem_hog.py &
echo "Started memory hog process."
sleep 3
echo ""

# Step 3: INVESTIGATE
echo "═══ Step 3: INVESTIGATING ═══"
echo "--- Top CPU consumers ---"
ps aux --sort=-%cpu | head -10
echo ""

echo "--- Finding processes by name ---"
echo "CPU hogs:"
pgrep -a cpu_hog || echo "  (none found)"
echo "Memory hog:"
pgrep -a mem_hog || echo "  (none found)"
echo ""

echo "--- Per-process resource usage ---"
top -b -n 1 | head -20
echo ""

# Inspect a CPU hog process
CPU_PID=$(pgrep -f cpu_hog | head -1)
if [ -n "$CPU_PID" ]; then
  echo "--- Inspecting CPU hog PID: $CPU_PID ---"
  cat /proc/$CPU_PID/status 2>/dev/null | grep -E "^(Name|State|VmRSS|VmSize|Threads)" || true
  echo "Command: $(cat /proc/$CPU_PID/cmdline 2>/dev/null | tr '\0' ' ')"
  echo "Executable: $(ls -la /proc/$CPU_PID/exe 2>/dev/null)"
fi
echo ""

# Step 4: RESOLVE — Kill the offenders
echo "═══ Step 4: RESOLVING — Killing offending processes ═══"
echo "Killing CPU hogs..."
pkill -f cpu_hog.sh 2>/dev/null || true
echo "Killing memory hog..."
pkill -f mem_hog.py 2>/dev/null || true
sleep 1
echo ""

# Step 5: Verify they're gone
echo "═══ Step 5: Verifying cleanup ═══"
echo "CPU hogs remaining: $(pgrep -c -f cpu_hog 2>/dev/null || echo 0)"
echo "Memory hogs remaining: $(pgrep -c -f mem_hog 2>/dev/null || echo 0)"
echo ""

# Clean up
rm -f /tmp/cpu_hog.sh /tmp/mem_hog.py

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 1.4 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
