# The Complete Linux & Kubernetes SRE Troubleshooting Lab

**From Beginner to Enterprise-Grade Site Reliability Engineer**

*A hands-on, lab-driven guide with real-world scenarios*

---

## Overview

This repository contains a comprehensive, 5-level progressive training program for mastering Linux and Kubernetes troubleshooting as a Site Reliability Engineer. Each level builds on the previous one and includes theory, commands, real-world scenarios, and hands-on labs.

## Structure

| Level | Title | Target | Time | Directory |
|-------|-------|--------|------|-----------|
| 1 | [Linux Foundations for SRE](level-1-linux-foundations/) | Beginner | 20-25 hours | `level-1-linux-foundations/` |
| 2 | [Linux Deep Troubleshooting](level-2-deep-troubleshooting/) | Intermediate | 20-25 hours | `level-2-deep-troubleshooting/` |
| 3 | [Kubernetes Core Troubleshooting](level-3-k8s-core/) | Intermediate | 25-30 hours | `level-3-k8s-core/` |
| 4 | [Kubernetes Advanced Operations](level-4-k8s-advanced/) | Advanced | 25-30 hours | `level-4-k8s-advanced/` |
| 5 | [Enterprise SRE Practices](level-5-enterprise-sre/) | Expert | 20-25 hours | `level-5-enterprise-sre/` |

**Total estimated time: ~110 hours**

## Prerequisites

- A Linux system (Ubuntu 22.04/24.04 recommended)
- Basic command-line familiarity
- For Kubernetes labs: `kind`, `minikube`, or `kubeadm` cluster
- For multi-node labs: 3 VMs (1 control plane + 2 workers) with 4 CPU, 8GB RAM each

## Quick Start

```bash
# Clone the repository
git clone https://github.com/bmacharia/k8s-trouble-shooting-lab.git
cd k8s-trouble-shooting-lab

# Start with Level 1
cd level-1-linux-foundations
cat README.md

# Run a lab
cd labs
chmod +x *.sh
./lab-1.1-boot-analysis.sh
```

## Repository Layout

```
k8s-trouble-shooting-lab/
├── README.md                              # This file
├── cheatsheet.md                          # Top 50 Linux + Top 50 K8s commands
├── level-1-linux-foundations/
│   ├── README.md                          # Theory: boot process, systemd, filesystem, processes, networking, permissions
│   └── labs/
│       ├── lab-1.1-boot-analysis.sh
│       ├── lab-1.2-service-management.sh
│       ├── lab-1.3-disk-emergency.sh
│       ├── lab-1.4-process-investigation.sh
│       ├── lab-1.5-network-troubleshooting.sh
│       └── lab-1.6-permission-debugging.sh
├── level-2-deep-troubleshooting/
│   ├── README.md                          # Theory: USE/RED methods, CPU, memory, disk I/O, network, /proc & /sys
│   └── labs/
│       ├── lab-2.1-memory-pressure.sh
│       └── lab-2.2-system-diagnostic.sh   # Full SRE diagnostic report script
├── level-3-k8s-core/
│   ├── README.md                          # Theory: K8s architecture, kubectl, pod troubleshooting, services, nodes
│   └── labs/
│       ├── lab-3.1-broken-pods.yaml       # 5 broken pods to fix
│       └── lab-3.2-service-debug.yaml     # Broken service chain
├── level-4-k8s-advanced/
│   ├── README.md                          # Theory: etcd, certs, RBAC, quotas, storage
│   └── labs/
│       └── lab-4.1-fullstack-debug.yaml   # Broken 3-tier app
├── level-5-enterprise-sre/
│   ├── README.md                          # Theory: incident response, monitoring, best practices, interview prep
│   ├── manifests/
│   │   ├── alert-rules.yaml               # Prometheus alert rules
│   │   └── production-deployment.yaml     # Battle-tested deployment template
│   └── scripts/
│       └── incident-runbook.sh            # Incident response runbook
└── scripts/
    └── sre-diagnostic-report.sh           # Standalone diagnostic script
```

## How to Use This Guide

1. **Read the theory** in each level's `README.md`
2. **Run the labs** to practice hands-on troubleshooting
3. **Break things** intentionally and fix them
4. **Build muscle memory** with the [command cheatsheet](cheatsheet.md)

## Standalone Tools

- **[SRE Diagnostic Report](scripts/sre-diagnostic-report.sh)** - Run on any Linux system to get a full system health report
- **[Incident Runbook](level-5-enterprise-sre/scripts/incident-runbook.sh)** - Step-by-step Kubernetes incident response
- **[Command Cheatsheet](cheatsheet.md)** - Quick reference for the most important commands

## License

This project is open source and available for educational purposes.
