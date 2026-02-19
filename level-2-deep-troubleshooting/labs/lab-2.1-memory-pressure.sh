#!/bin/bash
# ================================================================
# Lab 2.1: Memory Pressure Investigation
# Level 2 - Linux Deep Troubleshooting
# Lab: Simulate and Diagnose Memory Issues
# ================================================================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Lab 2.1: Memory Pressure Investigation              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Check current memory state
echo "═══ Step 1: Current memory state ═══"
echo "=== Before ==="
free -h
echo ""

# Step 2: Start a memory consumer
echo "═══ Step 2: Starting memory consumer ═══"
python3 -c "
import time, os
data = []
print(f'PID: {os.getpid()}')
for i in range(100):
    data.append(bytearray(10 * 1024 * 1024))  # 10MB per iteration
    time.sleep(0.2)
    if i % 10 == 0:
        print(f'Allocated: {(i+1)*10} MB')
time.sleep(300)
" &
MEM_PID=$!
echo "Memory consumer PID: $MEM_PID"

sleep 5

# Step 3: Observe memory changes
echo ""
echo "═══ Step 3: Memory state during consumption ═══"
echo "=== During ==="
free -h
echo ""

# Step 4: Find the memory hog
echo "═══ Step 4: Finding the memory hog ═══"
ps aux --sort=-%mem | head -5
echo "---"
cat /proc/$MEM_PID/status 2>/dev/null | grep -E "^(Name|VmRSS|VmSize|VmSwap)" || echo "Process already exited"
echo ""

# Step 5: Watch vmstat for swap activity
echo "═══ Step 5: Monitoring swap activity (vmstat) ═══"
vmstat 1 5
echo ""

# Step 6: Check OOM score
echo "═══ Step 6: OOM score ═══"
if [ -f /proc/$MEM_PID/oom_score ]; then
  echo "OOM score: $(cat /proc/$MEM_PID/oom_score)"
  echo "OOM score adj: $(cat /proc/$MEM_PID/oom_score_adj)"
else
  echo "Process already exited."
fi
echo ""

# Step 7: Clean up
echo "═══ Step 7: Cleaning up ═══"
kill $MEM_PID 2>/dev/null || true
sleep 1
echo "=== After ==="
free -h
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 2.1 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
