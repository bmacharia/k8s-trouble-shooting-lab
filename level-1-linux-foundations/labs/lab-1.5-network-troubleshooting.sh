#!/bin/bash
# ================================================================
# Lab 1.5: Network Troubleshooting Drill
# Level 1 - Linux Foundations for SRE
# Lab: Systematic Network Diagnosis
# ================================================================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Lab 1.5: Network Troubleshooting Drill              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Scenario: A web service isn't reachable. Walk through the layers."
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Start a simple web server
echo "═══ Step 1: Starting a simple web server on port 8080 ═══"
python3 -m http.server 8080 &>/dev/null &
WEB_PID=$!
echo "Web server PID: $WEB_PID"
sleep 1
echo ""

# Step 2: Verify it's listening
echo "═══ Step 2: Verifying the server is listening ═══"
ss -tlnp | grep 8080 || echo "WARNING: Nothing listening on 8080!"
echo ""

# Step 3: Test connectivity
echo "═══ Step 3: Testing connectivity ═══"
curl -s http://localhost:8080 | head -5
echo ""

# Step 4: Check which process owns the port
echo "═══ Step 4: Checking port ownership ═══"
sudo lsof -i :8080 2>/dev/null || ss -tlnp | grep 8080
echo ""

# Step 5: Simulate a problem — kill the server
echo "═══ Step 5: Simulating an outage (killing the server) ═══"
kill $WEB_PID 2>/dev/null
sleep 1
echo "Server killed."
echo ""

# Step 6: Now troubleshoot the "outage"
echo "═══ Step 6: TROUBLESHOOTING the outage ═══"
echo ""
echo "=== Is anything listening on 8080? ==="
ss -tlnp | grep 8080 || echo "  Nothing! Port is not open."
echo ""

echo "=== Is the process running? ==="
pgrep -a "http.server" || echo "  Nothing! Process is dead."
echo ""

echo "=== Check if port is blocked by firewall ==="
sudo iptables -L INPUT -n 2>/dev/null | grep 8080 || echo "  No firewall rules for 8080."
echo ""

echo "=== DNS working? ==="
dig +short google.com 2>/dev/null || echo "  DNS check skipped (dig not installed)"
echo ""

echo "=== Default gateway reachable? ==="
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$GATEWAY" ]; then
  echo "  Gateway: $GATEWAY"
  ping -c 2 "$GATEWAY" 2>/dev/null || echo "  Gateway unreachable!"
else
  echo "  No default gateway found."
fi
echo ""

# Step 7: Fix — restart the service
echo "═══ Step 7: FIXING — Restarting the web server ═══"
python3 -m http.server 8080 &>/dev/null &
NEW_PID=$!
sleep 1
echo "New server PID: $NEW_PID"
curl -s http://localhost:8080 | head -3 && echo "Service restored!" || echo "Service still down!"
echo ""

# Cleanup
kill $NEW_PID 2>/dev/null

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 1.5 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
