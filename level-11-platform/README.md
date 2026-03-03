# Level 11: Platform Engineering

*"The best SRE builds systems where incidents don't happen."*

**Time estimate: 25-30 hours**

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [11.1 Helm](labs/lab-11.1-helm/) | Chart with broken hook; rollback under pressure | helm diff, helm hooks, atomic upgrades, helm rollback |
| [11.2 GitOps](labs/lab-11.2-gitops/) | ArgoCD sync failing; drift detected | ArgoCD Application CRD, sync waves, Kustomize overlays |
| [11.3 Operators](labs/lab-11.3-operators/) | CRD stuck in Terminating; operator in CrashLoop | Finalizers, operator logs, CRD schema validation |
| [11.4 Multi-tenancy](labs/lab-11.4-multitenancy/) | Team A affects Team B; no isolation | ResourceQuota, LimitRange, NetworkPolicy per namespace |
