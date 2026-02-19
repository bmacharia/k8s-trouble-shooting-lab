#!/bin/bash
# ================================================================
# Lab 1.6: Permission Debugging
# Level 1 - Linux Foundations for SRE
# Lab: Fix Permission Problems
# ================================================================

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        Lab 1.6: Permission Debugging                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "This lab requires sudo privileges."
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Create a test scenario
echo "═══ Step 1: Creating test scenario ═══"
sudo useradd -m labuser 2>/dev/null || echo "User labuser already exists"
sudo mkdir -p /opt/webapp/data
echo "config_value=secret" | sudo tee /opt/webapp/config.ini > /dev/null
echo "important data" | sudo tee /opt/webapp/data/records.db > /dev/null
sudo chmod 600 /opt/webapp/config.ini     # Only root can read
sudo chmod 700 /opt/webapp/data           # Only root can enter
echo "Created /opt/webapp with restrictive permissions."
echo ""

# Step 2: Try to access as labuser (should fail)
echo "═══ Step 2: Attempting access as labuser (should FAIL) ═══"
echo "Trying to read config.ini..."
sudo -u labuser cat /opt/webapp/config.ini 2>&1 || true
echo ""
echo "Trying to list data directory..."
sudo -u labuser ls /opt/webapp/data 2>&1 || true
echo ""

# Step 3: Diagnose with namei
echo "═══ Step 3: Diagnosing with namei ═══"
echo "--- Path to config.ini ---"
namei -l /opt/webapp/config.ini
echo ""
echo "--- Path to records.db ---"
namei -l /opt/webapp/data/records.db
echo ""

# Step 4: Fix it properly
echo "═══ Step 4: Fixing permissions ═══"
sudo chown -R labuser:labuser /opt/webapp
sudo chmod 750 /opt/webapp
sudo chmod 640 /opt/webapp/config.ini
sudo chmod 750 /opt/webapp/data
sudo chmod 640 /opt/webapp/data/records.db
echo "Permissions fixed."
echo ""

# Step 5: Verify
echo "═══ Step 5: Verifying access (should SUCCEED) ═══"
echo "Reading config.ini as labuser:"
sudo -u labuser cat /opt/webapp/config.ini
echo ""
echo "Listing data directory as labuser:"
sudo -u labuser ls -la /opt/webapp/data
echo ""

echo "--- Final permissions ---"
namei -l /opt/webapp/data/records.db
echo ""

# Clean up
echo "═══ Cleaning up ═══"
sudo userdel -r labuser 2>/dev/null || true
sudo rm -rf /opt/webapp
echo "Cleanup complete."
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 1.6 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
