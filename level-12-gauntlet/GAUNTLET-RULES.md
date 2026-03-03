# The Expert Gauntlet — Rules and Scoring

*"Under pressure, you fall to the level of your training, not your plans."*

---

## Rules

1. **No instructions.** You get a `kubectl apply -f` command and a symptom description.
2. **Timer starts** when you apply the manifests.
3. **Read the SPOILER only after** your first genuine debugging attempt (minimum 20 minutes).
4. **Track your commands.** Paste every command you ran and its output into a notes file.
   Review it after the lab — identify where you went wrong and what you should have done instead.
5. **Repeat until** the diagnosis + fix takes under 10 minutes per scenario.

---

## Scoring

| Time to Diagnosis | Tier |
|-------------------|------|
| Under 5 minutes   | Expert |
| 5-15 minutes      | Senior |
| 15-30 minutes     | Mid-level |
| 30-60 minutes     | Junior |
| > 60 minutes      | Keep practicing — and that's fine |

The goal isn't to go fast — it's to develop a systematic mental model.
Speed is a byproduct of that.

---

## The 60-Second Triage Protocol

Before touching anything, answer these four questions:

```
1. WHAT is the user-visible symptom?
   (not "pod is broken" — "users are seeing 503 on /api/checkout")

2. WHEN did it start?
   kubectl get events --sort-by='.lastTimestamp' -A | tail -20

3. WHAT CHANGED recently?
   kubectl rollout history deployment -n <namespace>
   git log --oneline -10  (check deployment repo)

4. WHICH LAYER is the problem?
   App → K8s API objects → Node → Network → Infrastructure
```

Only after answering all four do you start running diagnostic commands.

---

## Scenarios

| # | File | Symptom | Skills Tested |
|---|------|---------|---------------|
| 1 | gauntlet-01-silent-failure.yaml | Users see intermittent errors, all pods Running | Endpoints, label selectors, service routing |
| 2 | gauntlet-02-cascading-failure.yaml | Everything slows down then stops | NetworkPolicy DNS egress, dependency mapping |
| 3 | (manual) | OOM at 2am, every night | CronJob + memory leak detection |
| 4 | gauntlet-04-node-plague.yaml | DiskPressure on healthy-seeming node | inode exhaustion, crictl image cleanup |
| 5 | (manual) | kubectl is slow (15-30s per command) | etcd performance, compaction |
| 6 | (manual) | Rollout deployed, traffic stuck on old pods | Deployment label/selector mismatch |
| 7 | (manual) | Monday morning: cluster stopped over weekend | Certificate expiry |
| 8 | (manual) | CronJob stuck in Terminating | Finalizers, operator debugging |
| 9 | (manual) | Developers can't deploy — RBAC broken | RBAC audit, RoleBinding reconstruction |
| 10 | gauntlet-10-storage-outage.yaml | StatefulSet stuck in ContainerCreating | Local PV node affinity, storage topology |

---

## How to Set Up Manual Scenarios

### Scenario 3 — Mystery OOM at 2am

```bash
# Create a CronJob that runs every 2 minutes (for lab purposes)
# and gradually allocates memory until it hits the limit
kubectl create namespace gauntlet3

cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: memory-leak-sim
  namespace: gauntlet3
spec:
  schedule: "*/2 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: leaker
            image: alpine:3.18
            command:
            - sh
            - -c
            - |
              # Allocate memory incrementally until killed
              python3 -c "
              import time
              data = []
              for i in range(100):
                  data.append('x' * 10 * 1024 * 1024)  # 10MB per iteration
                  time.sleep(0.5)
              "
            resources:
              requests:
                memory: 64Mi
              limits:
                memory: 128Mi   # Will OOMKill after ~128MB
          restartPolicy: Never
EOF

# Wait 5 minutes, then diagnose why pods keep restarting and being OOMKilled
kubectl get pods -n gauntlet3 -w
```

### Scenario 5 — etcd Slow (Control Plane Meltdown)

```bash
# Simulate by filling etcd with large objects
# (only do this in a lab cluster)
kubectl create namespace gauntlet5

for i in $(seq 1 500); do
  kubectl create configmap stress-$i -n gauntlet5 \
    --from-literal=data=$(dd if=/dev/urandom bs=10k count=1 2>/dev/null | base64) \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
done

# Now observe API server latency
time kubectl get pods -A
# Should be noticeably slower than normal

# Diagnose and fix:
# 1. Check etcd db size
# 2. Run compaction
# 3. Run defrag
# 4. Observe API server latency return to normal
```

### Scenario 6 — Traffic Stuck on Old Pods

```bash
# Deploy v1
kubectl create deployment web -n default --image=nginx:1.24
kubectl expose deployment web --port=80 --target-port=80

# Deploy "v2" with a different label (simulating bad deploy)
kubectl create deployment web-v2 -n default --image=nginx:alpine
# web-v2 has label "app=web-v2" not "app=web"
# The service still points to "app=web"
# All traffic goes to web (v1) — zero to web-v2
# This is the "deployment succeeded but no traffic shifted" scenario
```

### Scenario 7 — Certificate Cliff

```bash
# Check your cert expiry:
sudo kubeadm certs check-expiration

# To simulate expired certs (without actually expiring them):
# Set your system clock forward by 1 year in a test VM
# sudo date -s "2026-01-01"
# Try kubectl get pods — it will fail with "certificate has expired"
# Restore the clock, then renew certs
```

---

## After Every Gauntlet: The Retrospective

Ask yourself these questions after each scenario:

1. **What was my first hypothesis?** Was it right or wrong?
2. **What command would have gotten me to the answer fastest?**
3. **Did I follow the symptom → layer → hypothesis → confirm pattern?**
   Or did I start randomly applying fixes?
4. **What would I add to a monitoring/alerting system to catch this earlier?**
5. **What would the postmortem look like?** Write 3 bullets: what happened, why, what prevents recurrence.
