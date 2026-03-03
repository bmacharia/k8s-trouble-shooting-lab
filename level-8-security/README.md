# Level 8: Security Hardening

*"In Kubernetes, the default answer to 'can this do X?' is often 'yes, unfortunately.'"*

**Time estimate: 20-25 hours**

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [8.1 RBAC](labs/lab-8.1-rbac/) | CI/CD has cluster-admin; app gets 403 in wrong namespace | ClusterRoleBinding audit, namespace-scoped roles, least privilege |
| [8.2 Pod Security](labs/lab-8.2-pod-security/) | Pods running as root with privileged containers | Pod Security Standards, securityContext, capability dropping |
| [8.3 Admission](labs/lab-8.3-admission/) | Policy blocks deployment of unlabelled images | Kyverno ClusterPolicy, admission webhooks |
| [8.4 Secrets](labs/lab-8.4-secrets/) | Secret in git history, no rotation strategy | External Secrets Operator, Sealed Secrets, encryption at rest |
