#!/bin/bash
# ================================================================
# Lab 1.1: Analyzing Your Boot Process
# Level 1 - Linux Foundations for SRE
# ================================================================

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Lab 1.1: Boot Process Analysis                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Exercise 1: How long did your system take to boot?
echo "═══ Exercise 1: Boot Time ═══"
systemd-analyze
echo ""

# Exercise 2: What are the 10 slowest services?
echo "═══ Exercise 2: 10 Slowest Services ═══"
systemd-analyze blame | head -10
echo ""

# Exercise 3: Find any boot errors
echo "═══ Exercise 3: Boot Errors (priority: error and above) ═══"
journalctl -b -p err --no-pager | tail -20
echo ""

echo "═══ Exercise 3b: Boot Warnings ═══"
journalctl -b -p warning --no-pager | tail -20
echo ""

# Exercise 4: Examine the critical boot chain
echo "═══ Exercise 4: Critical Boot Chain ═══"
systemd-analyze critical-chain
echo ""

# Exercise 5: Check if any services failed to start
echo "═══ Exercise 5: Failed Services ═══"
systemctl --failed
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "Document your findings:"
echo "  - Total boot time: (see Exercise 1)"
echo "  - Slowest service: (see Exercise 2)"
echo "  - Any failed services: (see Exercise 5)"
echo "  - Any error messages: (see Exercise 3)"
echo "═══════════════════════════════════════════════════════════"
