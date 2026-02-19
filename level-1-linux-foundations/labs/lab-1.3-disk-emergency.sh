#!/bin/bash
# ================================================================
# Lab 1.3: Disk Space Emergency
# Level 1 - Linux Foundations for SRE
# Lab: Simulate and Resolve a Full Disk
# ================================================================

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Lab 1.3: Disk Space Emergency                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "This lab requires sudo privileges."
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Step 1: Create a small test filesystem (100MB)
echo "═══ Step 1: Creating a 100MB test filesystem ═══"
dd if=/dev/zero of=/tmp/testdisk.img bs=1M count=100 2>&1
mkfs.ext4 -F /tmp/testdisk.img 2>&1
sudo mkdir -p /mnt/testdisk
sudo mount /tmp/testdisk.img /mnt/testdisk
echo "Test filesystem mounted at /mnt/testdisk"
df -h /mnt/testdisk
echo ""

# Step 2: Fill it up
echo "═══ Step 2: Filling the disk ═══"
sudo dd if=/dev/urandom of=/mnt/testdisk/bigfile1 bs=1M count=30 2>&1
sudo dd if=/dev/urandom of=/mnt/testdisk/bigfile2 bs=1M count=30 2>&1
sudo dd if=/dev/urandom of=/mnt/testdisk/bigfile3 bs=1M count=20 2>&1
echo ""

# Step 3: Check — it should be almost full
echo "═══ Step 3: Checking disk usage (should be nearly full) ═══"
df -h /mnt/testdisk
echo ""

# Step 4: Try to write — should fail
echo "═══ Step 4: Attempting to write more data (should fail) ═══"
sudo dd if=/dev/urandom of=/mnt/testdisk/bigfile4 bs=1M count=20 2>&1 || true
echo ""

# Step 5: TROUBLESHOOT — Find the largest files
echo "═══ Step 5: TROUBLESHOOTING — Finding largest files ═══"
sudo du -sh /mnt/testdisk/* 2>/dev/null | sort -rh
echo ""

# Step 6: RESOLVE — Remove the largest file
echo "═══ Step 6: RESOLVING — Removing largest file ═══"
sudo rm /mnt/testdisk/bigfile1
echo "Space after cleanup:"
df -h /mnt/testdisk
echo ""

# Step 7: Investigate inode exhaustion
echo "═══ Step 7: Investigating inodes ═══"
df -i /mnt/testdisk
echo ""

# Step 8: Create thousands of tiny files to exhaust inodes
echo "═══ Step 8: Exhausting inodes with tiny files ═══"
echo "Creating thousands of tiny files..."
for i in $(seq 1 50000); do
  sudo touch /mnt/testdisk/tiny_$i 2>/dev/null || break
done
echo "Inode usage after creating tiny files:"
df -i /mnt/testdisk
echo ""

# Step 9: Clean up
echo "═══ Step 9: Cleaning up ═══"
sudo umount /mnt/testdisk
sudo rm /tmp/testdisk.img
sudo rmdir /mnt/testdisk
echo "Cleanup complete."
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Lab 1.3 Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
