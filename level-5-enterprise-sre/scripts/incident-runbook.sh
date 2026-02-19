#!/bin/bash
# ================================================================
# INCIDENT RESPONSE RUNBOOK
# Quick assessment for Kubernetes incidents
#
# Usage: ./incident-runbook.sh
#
# Severity: P1/P2/P3/P4
# Impact: What's broken for users?
# Duration: Start -> End
# ================================================================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           INCIDENT RESPONSE RUNBOOK                      ║"
echo "║           $(date)                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "════ STEP 1: ASSESS CLUSTER HEALTH ════"
kubectl get nodes
echo ""
kubectl top nodes 2>/dev/null || echo "(metrics-server not available)"
echo ""
echo "Non-running pods:"
kubectl get pods -A --field-selector status.phase!=Running 2>/dev/null | head -20
echo ""

echo "════ STEP 2: CHECK RECENT EVENTS ════"
kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | tail -30
echo ""

echo "════ STEP 3: CHECK RECENT DEPLOYMENTS (what changed?) ════"
kubectl get deploy -A -o json 2>/dev/null | jq -r '
  .items[] | select(.metadata.annotations["deployment.kubernetes.io/revision"]) |
  "\(.metadata.namespace)/\(.metadata.name) revision=\(.metadata.annotations["deployment.kubernetes.io/revision"])"' 2>/dev/null || echo "(jq not available or no deployments)"
echo ""

echo "════ STEP 4: CHECK PROBLEM PODS ════"
for pod in $(kubectl get pods -A --field-selector status.phase!=Running -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  ns=$(echo "$pod" | cut -d/ -f1)
  name=$(echo "$pod" | cut -d/ -f2)
  echo "--- $pod ---"
  kubectl describe pod "$name" -n "$ns" 2>/dev/null | grep -A 10 "Events:" || true
  echo ""
done

echo "════ STEP 5: QUICK MITIGATIONS ════"
echo "Rollback a deployment:"
echo "  kubectl rollout undo deployment/<name> -n <namespace>"
echo ""
echo "Scale up:"
echo "  kubectl scale deployment/<name> --replicas=<N> -n <namespace>"
echo ""
echo "Restart a deployment:"
echo "  kubectl rollout restart deployment/<name> -n <namespace>"
echo ""

echo "════ RUNBOOK COMPLETE ════"
