# Lab 8.1 — RBAC: Over-Privilege Audit and Namespace Scoping

## Symptoms

- App logs show `403 Forbidden` when trying to read ConfigMaps in `team-prod`.
- Security scan flags the CI/CD service account as having `cluster-admin`.
- No one knows how these bindings were created or what they do.

---

## Lab Setup

```bash
kubectl apply -f 01-rbac-broken.yaml
```

---

## The RBAC Data Model

```
Who           →   What actions     →   On what resources
(Subject)         (Verbs)              (Resources in Namespace)

Subject:
  User, Group, ServiceAccount

Verb: get, list, watch, create, update, patch, delete

Role (namespaced):        Defines permissions within ONE namespace
ClusterRole (global):     Defines permissions cluster-wide OR as a template for namespaces

RoleBinding (namespaced): Grants a Role OR ClusterRole within ONE namespace
ClusterRoleBinding:       Grants a ClusterRole cluster-wide
```

**The most common mistake:** Creating a Role in namespace A but binding it to a subject
that lives in namespace B, then wondering why it doesn't work.

---

## Step 1 — Audit: Who Has cluster-admin?

```bash
# Find EVERY subject with cluster-admin — run this first in any new cluster
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] |
    select(.roleRef.name == "cluster-admin") |
    "Binding: \(.metadata.name)\nSubjects: \(.subjects // [] | map("\(.kind)/\(.name) in \(.namespace // "cluster")") | join(", "))\n"'

# Alternative: use kubectl-who-can plugin
kubectl who-can '*' '*' --all-namespaces   # Who has full access?

# Check a specific service account
kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:team-dev:cicd-runner
# "yes" → this SA has cluster-admin or equivalent
```

---

## Step 2 — Audit: What Can a Service Account Do?

```bash
# List ALL permissions for a service account
kubectl auth can-i --list \
  --as=system:serviceaccount:team-dev:cicd-runner

# Check specific actions
kubectl auth can-i delete pods -A \
  --as=system:serviceaccount:team-dev:cicd-runner
kubectl auth can-i delete nodes \
  --as=system:serviceaccount:team-dev:cicd-runner
kubectl auth can-i create clusterrolebindings \
  --as=system:serviceaccount:team-dev:cicd-runner
# Any "yes" to these → massive security risk for a CI/CD runner
```

---

## Step 3 — Diagnose the web-app 403 Error

```bash
# Check if web-app can read ConfigMaps in team-prod
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:team-prod:web-app \
  -n team-prod
# Expected: "no" (the binding is in the wrong namespace)

# Find all RoleBindings for web-app
kubectl get rolebindings -A -o json | \
  jq '.items[] | select(.subjects[]? | .name == "web-app" and .kind == "ServiceAccount")'

# Find all ClusterRoleBindings for web-app
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.subjects[]? | .name == "web-app")'

# You will find the binding is in team-dev, not team-prod
# A binding in team-dev gives access to resources in team-dev ONLY
```

---

## Step 4 — Trace the "Forbidden" Error to an RBAC Rule

```bash
# Enable audit logging (if available) to see exactly which RBAC check failed
# In kube-apiserver audit log, look for:
# "authorization.k8s.io/reason": "RBAC: clusterrole ... not found"

# Or reproduce the 403 manually
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:team-prod:web-app \
  -n team-prod
# Output: "no" → confirms the problem

# What would make this "yes"?
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:team-prod:web-app \
  -n team-dev
# If "yes" here but "no" in team-prod → binding is in the wrong namespace
```

---

## Log Analysis

```bash
# API server logs show RBAC denials
kubectl logs -n kube-system -l component=kube-apiserver --tail=100 | \
  grep -i "forbidden\|rbac\|unauthorized"

# Application logs showing 403
kubectl logs -n team-prod -l app=web-app --tail=50 | grep -i "403\|forbidden\|unauthorized"

# Events in the affected namespace
kubectl get events -n team-prod --sort-by='.lastTimestamp' | grep -i "forbidden"
```

---

## Common Causes

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | App gets 403 on API calls | No RBAC permission granted | Create Role + RoleBinding in correct namespace |
| 2 | RoleBinding exists but ignored | Binding in wrong namespace | Move RoleBinding to namespace where resources live |
| 3 | Security audit flags SA | ClusterRoleBinding with cluster-admin | Replace with scoped Role + RoleBinding |
| 4 | User can't access resource | Using ClusterRole but no ClusterRoleBinding | Create ClusterRoleBinding or RoleBinding in target ns |
| 5 | Permissions work in dev, not prod | Different namespace names | Verify binding namespace matches resource namespace |

---

## Resolution

```bash
# Remove the over-privileged cluster-admin binding
kubectl delete clusterrolebinding cicd-runner-cluster-admin

# Apply the scoped permissions
kubectl apply -f 02-solution.yaml

# Verify CI/CD runner lost cluster-admin
kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:team-dev:cicd-runner
# Expected: "no"

# Verify CI/CD runner can still deploy to team-dev
kubectl auth can-i create deployments \
  --as=system:serviceaccount:team-dev:cicd-runner \
  -n team-dev
# Expected: "yes"

# Verify web-app can now read ConfigMaps in team-prod
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:team-prod:web-app \
  -n team-prod
# Expected: "yes"

# Verify web-app cannot read Secrets (not in its permissions)
kubectl auth can-i get secrets \
  --as=system:serviceaccount:team-prod:web-app \
  -n team-prod
# Expected: "no"
```

---

## Prevention

```bash
# 1. Regular audit — run this monthly:
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name == "cluster-admin") | .metadata.name'

# 2. Never use kubectl create clusterrolebinding ... --clusterrole=cluster-admin
#    during debugging without immediate cleanup

# 3. Principle: use the most narrowly-scoped role possible
#    ClusterRoleBinding → only if access to ALL namespaces is truly needed
#    RoleBinding → for single-namespace access (even if using a ClusterRole)

# 4. Use the view, edit, admin ClusterRoles as templates for common patterns:
#    view  → read-only on common resources
#    edit  → read/write on most resources, no RBAC
#    admin → full namespace access, can create RBAC

# 5. Audit newly created ClusterRoleBindings in CI/CD — detect cluster-admin creations
```

---

## Cleanup

```bash
kubectl delete -f 01-rbac-broken.yaml --ignore-not-found
kubectl delete -f 02-solution.yaml --ignore-not-found
kubectl delete namespace team-dev team-prod --ignore-not-found
```
