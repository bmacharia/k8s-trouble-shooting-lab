# Lab 8.2 — Pod Security Standards: From Privileged to Restricted

## Symptoms

- Security audit finds pods running as root, with privileged containers, or with host access.
- After enforcing Pod Security Standards on the namespace, pods fail to start.
- App team says "the pod needs to run as root to work."

---

## Lab Setup

```bash
kubectl apply -f 01-insecure-pods.yaml

# You will see warnings immediately (namespace is in warn mode):
# Warning: would violate PodSecurity "restricted:latest": ...

kubectl get pods -n secure-ns
```

---

## The Three Pod Security Standard Levels

```
Privileged  — No restrictions. Used for system components (CNI, CSI, monitoring agents).
              Any pod can run privileged, use host namespaces, etc.

Baseline    — Prevents the worst exploits. Disallows:
              privileged containers, hostNetwork, hostPID, hostIPC,
              dangerous capabilities (SYS_ADMIN, NET_ADMIN, etc.)

Restricted  — Heavily restricted. Requires:
              runAsNonRoot, drop ALL capabilities, no privilege escalation,
              seccomp profile, read-only root filesystem (recommended)
```

---

## Step 1 — Scan for Violations Before Enforcing

```bash
# See what would fail if you enforced restricted NOW
# (namespace must have warn or audit labels — not enforce)
kubectl apply -f 01-insecure-pods.yaml 2>&1 | grep -i "warning\|violat"

# Dry-run check what violations exist in a namespace
kubectl label namespace secure-ns \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  --overwrite

# Violations appear in API server audit logs:
kubectl logs -n kube-system -l component=kube-apiserver --tail=200 | \
  grep "pod-security"
```

---

## Step 2 — Understand Each Violation

```bash
# Check a pod's security context
kubectl get pod insecure-root -n secure-ns -o yaml | grep -A 30 "securityContext"

# Privileged container check
kubectl get pod insecure-privileged -n secure-ns \
  -o jsonpath='{.spec.containers[0].securityContext.privileged}'
# Output: true → CRITICAL VIOLATION

# Host namespace checks
kubectl get pod insecure-host-access -n secure-ns \
  -o jsonpath='{.spec.hostNetwork}{.spec.hostPID}'
# Output: truetrue → violations

# Check running user
kubectl exec -n secure-ns insecure-root -- id
# Output: uid=0(root) → running as root
```

---

## Step 3 — Move from Warn to Enforce

```bash
# First, fix all pods. Then enable enforcement.
# Enforce will BLOCK pod creation that violates the policy.

kubectl label namespace secure-ns \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  --overwrite

# Test: try to create a privileged pod — it should be rejected
kubectl run test-priv -n secure-ns --image=alpine \
  --overrides='{"spec":{"containers":[{"name":"c","image":"alpine","securityContext":{"privileged":true}}]}}'
# Expected: Error from server (Forbidden): pods "test-priv" is forbidden:
#   violates PodSecurity "restricted:latest": privileged
```

---

## Step 4 — Fix Each Violation

```bash
# Violation: runs as root
# Fix: add runAsNonRoot: true + runAsUser: <non-zero UID>

# Violation: allowPrivilegeEscalation: true (or not set)
# Fix: set allowPrivilegeEscalation: false

# Violation: no capabilities dropped
# Fix: add capabilities.drop: ["ALL"]

# Violation: readOnlyRootFilesystem not set
# Fix: set readOnlyRootFilesystem: true
#      Then mount emptyDir volumes for paths the app needs to write to

# Violation: no seccomp profile
# Fix: add seccompProfile.type: RuntimeDefault to pod spec securityContext

# Violation: hostNetwork: true
# Fix: remove it — almost never needed for application pods

# Violation: hostPID: true
# Fix: remove it — only needed for node-level debugging tools
```

---

## Common Causes and Patterns

| Violation | Risk | Fix |
|-----------|------|-----|
| `privileged: true` | Full host escape possible | Remove; redesign the workload |
| `runAsRoot` / no `runAsNonRoot` | Process exploits have root access | Set `runAsNonRoot: true` and `runAsUser: 1000` |
| No capabilities drop | Extra kernel capabilities (NET_RAW, etc.) | `capabilities.drop: [ALL]` |
| `allowPrivilegeEscalation: true` | Child processes can gain more privilege | Set to `false` |
| `readOnlyRootFilesystem: false` | Attacker can modify container files | Set to `true`, add emptyDir for writable paths |
| `hostNetwork: true` | Can reach host network interfaces | Remove — use K8s Services instead |
| `hostPID: true` | Can see all host processes, send signals | Remove — never needed for apps |

---

## The "App Must Run as Root" Conversation

When a developer says the app needs root, investigate:

```bash
# What does it actually need root for?
# 1. Binding port < 1024 → use NET_BIND_SERVICE capability instead
#    securityContext.capabilities.add: ["NET_BIND_SERVICE"]
#    OR: just use a port > 1024 and put the Service on port 80

# 2. Writing to /etc or /var → use ConfigMap mounts and emptyDir volumes

# 3. The image runs as root by default → use USER directive in Dockerfile
#    Or add runAsUser in the pod spec

# 4. Installing software at runtime → redesign — install in the image instead
#    This is a container anti-pattern
```

---

## Resolution

```bash
# Apply the secure pod
kubectl apply -f 02-solution.yaml

# Verify it runs
kubectl get pod secure-app -n secure-ns

# Verify it is non-root
kubectl exec -n secure-ns secure-app -- id
# Expected: uid=1000 gid=3000 groups=2000

# Verify capabilities are dropped
kubectl exec -n secure-ns secure-app -- cat /proc/1/status | grep CapEff
# All zeros = no capabilities

# Now enforce restricted on the namespace
kubectl label namespace secure-ns \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite

# Delete the insecure pods
kubectl delete pod insecure-root insecure-privileged insecure-host-access -n secure-ns
```

---

## Prevention

```bash
# 1. Enforce restricted on all application namespaces
#    Use Privileged only for kube-system and infra namespaces

# 2. Set warn and audit modes first (1-2 weeks) before enforce
#    This finds violations without breaking production

# 3. Use Kyverno or OPA to create custom policies for org-specific requirements
#    e.g. "all images must come from our registry"

# 4. Run kube-bench to check the full CIS benchmark:
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs -l app=kube-bench
```

---

## Cleanup

```bash
kubectl delete namespace secure-ns
```
