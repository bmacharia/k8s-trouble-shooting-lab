# The Complete Linux & Kubernetes SRE Troubleshooting Lab

**From Beginner to Kubernetes Expert**

*A hands-on, lab-driven guide built from real production failure patterns*

---

## Overview

A comprehensive, 12-level progressive training program for mastering Linux and Kubernetes
from beginner to expert. Each level builds on the previous one with broken manifests to fix,
systematic runbooks, and production-grade scenarios.

Every lab follows the same format:
- `00-setup.yaml` — namespace and prerequisites
- `01-*.yaml` — the workloads
- `02-*-broken.yaml` — the deliberately broken state
- `03-solution.yaml` — the fix
- `RUNBOOK.md` — systematic debugging guide with copy-paste commands

## Structure

### Foundation (Levels 1-2): Linux
| Level | Title | Target | Time |
|-------|-------|--------|------|
| 1 | [Linux Foundations for SRE](level-1-linux-foundations/) | Beginner | 20-25 hrs |
| 2 | [Linux Deep Troubleshooting](level-2-deep-troubleshooting/) | Intermediate | 20-25 hrs |

### Core Kubernetes (Levels 3-5)
| Level | Title | Target | Time |
|-------|-------|--------|------|
| 3 | [Kubernetes Core Troubleshooting](level-3-k8s-core/) | Intermediate | 25-30 hrs |
| 4 | [Kubernetes Advanced Operations](level-4-k8s-advanced/) | Advanced | 25-30 hrs |
| 5 | [Enterprise SRE Practices](level-5-enterprise-sre/) | Advanced | 20-25 hrs |

### Expert Kubernetes (Levels 6-12)
| Level | Title | Target | Time |
|-------|-------|--------|------|
| 6 | [Networking Mastery](level-6-networking/) | Expert | 20-25 hrs |
| 7 | [Workloads & Scheduling](level-7-workloads/) | Expert | 20-25 hrs |
| 8 | [Security Hardening](level-8-security/) | Expert | 20-25 hrs |
| 9 | [Cluster Lifecycle](level-9-cluster-lifecycle/) | Expert | 20-25 hrs |
| 10 | [Observability Stack](level-10-observability/) | Expert | 20-25 hrs |
| 11 | [Platform Engineering](level-11-platform/) | Expert | 25-30 hrs |
| 12 | [The Gauntlet](level-12-gauntlet/) | Expert | 20 hrs (repeat) |

**Total: ~240 hours of hands-on practice**

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

1. **Read the level README** — understand the concepts and failure modes
2. **Apply the setup manifests** — spin up the broken scenario
3. **Attempt diagnosis** using only the RUNBOOK — no peeking at the solution
4. **Apply the solution** only after forming a hypothesis and confirming it
5. **Repeat the gauntlet** (Level 12) until diagnosis takes under 10 minutes

## Expert Curriculum

See **[EXPERT-CURRICULUM.md](EXPERT-CURRICULUM.md)** for:
- The complete skill tree from practitioner to expert
- What each level covers and what gap it fills
- Recommended practice schedule (16 weeks)
- The 10 questions you must answer without searching to be called an expert

## Standalone Tools

- **[SRE Diagnostic Report](scripts/sre-diagnostic-report.sh)** - Run on any Linux system to get a full system health report
- **[Incident Runbook](level-5-enterprise-sre/scripts/incident-runbook.sh)** - Step-by-step Kubernetes incident response
- **[Command Cheatsheet](cheatsheet.md)** - Quick reference for the most important commands

## License

This project is open source and available for educational purposes.
