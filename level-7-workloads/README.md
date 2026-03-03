# Level 7: Workloads, Scheduling, and Autoscaling

*"Understanding workload types is what separates ops from platform engineers."*

**Time estimate: 20-25 hours**

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [7.1 StatefulSets](labs/lab-7.1-statefulsets/) | Redis StatefulSet stuck at 1/3 | Ordered startup, headless service, PVC templates, StorageClass |
| [7.2 Jobs & CronJobs](labs/lab-7.2-jobs-cronjobs/) | CronJob silently never runs, Job rejected | restartPolicy, cron expressions, TTL, concurrencyPolicy |
| [7.3 Scheduling](labs/lab-7.3-scheduling/) | Pods Pending, drain hangs | nodeSelector, taints/tolerations, anti-affinity, PDB |
| [7.4 Autoscaling](labs/lab-7.4-autoscaling/) | HPA never scales, thrashing on scale-down | HPA target ref, resource requests, stabilizationWindow |

---

## Prerequisites

- Completed Level 6 (or strong understanding of K8s networking)
- metrics-server installed (for Lab 7.4)
- A StorageClass available (for Lab 7.1)
