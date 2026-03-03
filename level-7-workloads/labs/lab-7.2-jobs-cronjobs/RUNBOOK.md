# Lab 7.2 — Jobs and CronJobs: Silent Batch Failures

## Symptoms

- **Job:** `kubectl apply` rejected immediately with a validation error.
- **CronJob:** Created successfully, but the job never runs — no pods, no events.
  The team assumes it worked because there were no errors.
- Older completed Jobs are piling up across all namespaces.

---

## Lab Setup

```bash
# This will fail on purpose — that is the lab
kubectl apply -f 01-job-broken.yaml
# Read the error message

kubectl apply -f 02-cronjob-broken.yaml
# This will succeed — but the job will never run
```

---

## Jobs vs Deployments: Key Differences

```
Deployment:   runs forever, always restarts, restartPolicy: Always required
Job:          runs to completion, restartPolicy must be Never or OnFailure
CronJob:      creates a new Job on a schedule, does NOT re-use the same Job
```

---

## Diagnosing the Job restartPolicy Error

```bash
# Apply the broken job and read the error
kubectl apply -f 01-job-broken.yaml
# Error: Job.batch "data-processor" is invalid:
#   spec.template.spec.restartPolicy: Unsupported value: "Always":
#   supported values: "OnFailure", "Never"

# Fix: restartPolicy must be OnFailure or Never
# Use OnFailure when: the command might fail transiently and should be retried in the same pod
# Use Never when: you want a fresh pod for each attempt (better isolation, cleaner logs)
```

---

## Diagnosing the CronJob That Never Fires

### Step 1 — Check if the CronJob exists and its schedule

```bash
kubectl get cronjob nightly-report
# Output shows:
# NAME            SCHEDULE       SUSPEND  ACTIVE  LAST SCHEDULE   AGE
# nightly-report  0 25 * * *     False    0       <none>          5m

# "LAST SCHEDULE: <none>" after several minutes → job has never been triggered
```

### Step 2 — Validate the cron expression

```bash
# Check the schedule
kubectl get cronjob nightly-report -o jsonpath='{.spec.schedule}'
# Output: 0 25 * * *

# Validate it:
# Format: minute hour day month weekday
# "0 25 * * *" = minute 0, hour 25 → INVALID (hours are 0-23)
# This is silently accepted by Kubernetes but never fires

# Quick validation tool (if available)
echo "0 25 * * *" | cron-validator
# OR use https://crontab.guru to verify expressions

# Common valid examples:
# "0 2 * * *"      = 2:00 AM daily
# "*/5 * * * *"    = every 5 minutes
# "0 9 * * 1"      = 9:00 AM every Monday
# "0 0 1 * *"      = midnight on the 1st of every month
```

### Step 3 — Check if the CronJob is suspended

```bash
kubectl get cronjob nightly-report -o jsonpath='{.spec.suspend}'
# false = not suspended
# true  = suspended (manually or by an operator) → will never fire
```

### Step 4 — Manually trigger the CronJob to test it

```bash
# Force the CronJob to run NOW (bypasses schedule entirely)
kubectl create job --from=cronjob/nightly-report manual-test

# Watch the result
kubectl get pods -l job-name=manual-test
kubectl logs -l job-name=manual-test
```

### Step 5 — Check for accumulated completed Jobs (the bloat problem)

```bash
# List all Jobs with their status
kubectl get jobs -A --sort-by=.metadata.creationTimestamp

# Count completed Jobs per namespace
kubectl get jobs -A --field-selector status.successful=1 | wc -l

# If there are hundreds of old jobs → they are consuming etcd space
# Check if they have TTL set:
kubectl get jobs -A -o json | \
  jq '.items[] | {name: .metadata.name, ttl: .spec.ttlSecondsAfterFinished}'
# If ttl is null → jobs never auto-delete

# Emergency cleanup: delete all completed jobs in a namespace
kubectl delete jobs -n default --field-selector status.successful=1
```

### Step 6 — Check the startingDeadlineSeconds risk

```bash
# Get the current setting
kubectl get cronjob nightly-report \
  -o jsonpath='{.spec.startingDeadlineSeconds}'
# null = not set

# Without startingDeadlineSeconds:
# If Kubernetes misses 100+ scheduled runs (e.g., cluster was down all weekend)
# the CronJob controller will STOP scheduling the job permanently
# (CronJob controller gives up after 100 missed schedules)

# With startingDeadlineSeconds: 3600
# "If the job can't start within 1 hour of its scheduled time, skip that run"
# Prevents the 100-missed-schedule lockout
```

---

## Log Analysis

```bash
# CronJob controller logs (inside kube-controller-manager)
kubectl logs -n kube-system -l component=kube-controller-manager --tail=200 | \
  grep -i "cronjob\|nightly-report"

# Check CronJob events
kubectl describe cronjob nightly-report | grep -A 10 Events

# Job failure events
kubectl get events --sort-by='.lastTimestamp' | grep -i "job\|backoff"

# Pod logs from a job run
kubectl logs -l job-name=nightly-report-<timestamp>
# OR get the most recent job:
LATEST_JOB=$(kubectl get jobs -l app=nightly-report --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -l job-name=$LATEST_JOB
```

---

## Common Causes

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | Job rejected at apply | `restartPolicy: Always` | Change to `Never` or `OnFailure` |
| 2 | CronJob never fires | Invalid schedule (hour > 23, etc.) | Fix cron expression |
| 3 | CronJob never fires | `spec.suspend: true` | `kubectl patch cronjob <name> -p '{"spec":{"suspend":false}}'` |
| 4 | CronJob stopped after cluster downtime | 100+ missed schedules without deadline | Set `startingDeadlineSeconds` |
| 5 | Old jobs accumulating | No `ttlSecondsAfterFinished` | Set TTL on jobTemplate.spec |
| 6 | Job runs but always fails | Wrong command or missing env | Check pod logs with `--previous` |
| 7 | Concurrent jobs causing conflicts | `concurrencyPolicy: Allow` | Change to `Forbid` or `Replace` |

---

## Resolution

```bash
# Fix the Job
kubectl delete job data-processor --ignore-not-found
kubectl apply -f 03-solution.yaml

# Watch the job complete
kubectl get pods -w
kubectl logs -l job-name=data-processor

# Fix the CronJob
kubectl delete cronjob nightly-report
kubectl apply -f 03-solution.yaml

# Verify the fixed schedule
kubectl get cronjob nightly-report
# Should show a valid SCHEDULE and LAST SCHEDULE after the next trigger time

# Manual test to confirm it works
kubectl create job --from=cronjob/nightly-report test-now
kubectl logs -l job-name=test-now
# Expected: "Generating nightly report... Report complete."
```

---

## Prevention

```bash
# 1. Always validate cron expressions before applying
#    Use: https://crontab.guru (paste your expression and verify human-readable output)

# 2. Always set ttlSecondsAfterFinished on Jobs and CronJob jobTemplates
#    Recommended: 86400 (1 day) for daily jobs, 3600 (1 hour) for frequent jobs

# 3. Always set startingDeadlineSeconds on CronJobs
#    Recommended: at least 2× the interval between runs

# 4. Always set concurrencyPolicy explicitly — never rely on the default (Allow)
#    Forbid: safest for stateful batch jobs
#    Replace: good for idempotent jobs that should always run the latest version

# 5. Alert on Job failures:
#    Prometheus query: kube_job_status_failed > 0

# 6. After creating a CronJob, always do an immediate manual trigger test:
kubectl create job --from=cronjob/<name> smoke-test
```

---

## Cleanup

```bash
kubectl delete job data-processor manual-test test-now --ignore-not-found
kubectl delete cronjob nightly-report --ignore-not-found
```
