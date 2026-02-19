#!/bin/bash
# ================================================================
# Lab 1.2: Systemd Service Management
# Level 1 - Linux Foundations for SRE
# Lab: Create, Break, and Fix a Service
# ================================================================

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Lab 1.2: Systemd Service Management                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "This lab requires sudo privileges."
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Create a simple application
echo "═══ Step 1: Creating a simple application ═══"
sudo mkdir -p /opt/labapp
cat <<'SCRIPT' | sudo tee /opt/labapp/server.sh
#!/bin/bash
echo "Server starting on port 8888..."
while true; do
  echo "$(date): Server is running" >> /opt/labapp/server.log
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello from labapp" | \
    nc -l -p 8888 -q 1 2>/dev/null || true
done
SCRIPT
sudo chmod +x /opt/labapp/server.sh
echo "Application created at /opt/labapp/server.sh"
echo ""

# Step 2: Create a systemd service
echo "═══ Step 2: Creating systemd service ═══"
cat <<'UNIT' | sudo tee /etc/systemd/system/labapp.service
[Unit]
Description=Lab Application Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/labapp/server.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
echo "Service unit file created."
echo ""

# Step 3: Enable and start the service
echo "═══ Step 3: Enabling and starting the service ═══"
sudo systemctl daemon-reload
sudo systemctl enable --now labapp
sleep 2
echo ""

# Step 4: Verify it's running
echo "═══ Step 4: Verifying service status ═══"
systemctl status labapp --no-pager || true
echo ""

# Step 5: View the logs
echo "═══ Step 5: Recent logs ═══"
journalctl -u labapp --no-pager | tail -5
echo ""

# Step 6: BREAK IT
echo "═══ Step 6: BREAKING the service (changing script path) ═══"
sudo sed -i 's|/opt/labapp/server.sh|/opt/labapp/doesnt-exist.sh|' \
  /etc/systemd/system/labapp.service
sudo systemctl daemon-reload
sudo systemctl restart labapp 2>/dev/null || true
sleep 2
echo ""

# Step 7: DIAGNOSE IT
echo "═══ Step 7: DIAGNOSING the broken service ═══"
echo "--- Service Status ---"
systemctl status labapp --no-pager 2>/dev/null || true
echo ""
echo "--- Recent Logs ---"
journalctl -u labapp --since "1 min ago" --no-pager 2>/dev/null || true
echo ""
echo "--- Configured ExecStart ---"
systemctl show labapp -p ExecStart
echo ""

# Step 8: FIX IT
echo "═══ Step 8: FIXING the service ═══"
sudo sed -i 's|/opt/labapp/doesnt-exist.sh|/opt/labapp/server.sh|' \
  /etc/systemd/system/labapp.service
sudo systemctl daemon-reload
sudo systemctl restart labapp
sleep 2
echo "--- Status after fix ---"
systemctl status labapp --no-pager || true
echo ""

# Step 9: Clean up
echo "═══ Step 9: Cleaning up ═══"
sudo systemctl disable --now labapp 2>/dev/null || true
sudo rm -f /etc/systemd/system/labapp.service
sudo systemctl daemon-reload
sudo rm -rf /opt/labapp
echo "Cleanup complete."
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 1.2 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
