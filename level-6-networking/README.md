# Level 6: Kubernetes Networking Mastery

*"Most production incidents are networking problems in disguise."*

**Time estimate: 20-25 hours**

---

## Why Networking is the Hardest Layer

Kubernetes networking has 4 independent layers that each break differently:

```
Layer 4: Application (wrong port, bad config, crash)
Layer 3: Kubernetes (Service selector, NetworkPolicy, DNS, Ingress)
Layer 2: CNI (pod CIDR, routing, overlay, IP allocation)
Layer 1: Host (iptables, kernel routing, MTU, firewall)
```

The difficulty: a failure at Layer 1 looks identical to a failure at Layer 3 until
you know exactly where to look. This level teaches you to navigate all four layers.

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [6.1 CNI Deep Dive](labs/lab-6.1-cni-deep-dive/) | Pod cannot reach pod across namespaces | NetworkPolicy namespace labels, CNI routing, packet tracing |
| [6.2 Service Networking](labs/lab-6.2-service-networking/) | 503s and intermittent NodePort drops | targetPort, ClusterIP iptables, externalTrafficPolicy |
| [6.3 Ingress](labs/lab-6.3-ingress/) | 503 on all paths, 413 on upload | Backend service names, nginx annotations, body size limits |
| [6.4 NetworkPolicy](labs/lab-6.4-networkpolicy/) | DNS fails, backend cannot reach DB | Default-deny + DNS egress, podSelector label mismatch |
| [6.5 CoreDNS](labs/lab-6.5-coredns/) | External DNS intermittently fails | Corefile, upstream forwarders, ndots, cache TTL |

---

## Prerequisites

- Completed Levels 1-5
- A running cluster (kind, minikube, or kubeadm)
- For Lab 6.3: nginx-ingress-controller installed
- For Lab 6.5: access to modify the `kube-system` namespace (use a lab cluster!)

---

## Running Order

Work through labs in order — each one builds on mental models from the previous.

```bash
# Quick start
cd labs/lab-6.1-cni-deep-dive
cat RUNBOOK.md        # Read the runbook first
kubectl apply -f 00-setup.yaml
kubectl apply -f 01-workloads.yaml
kubectl apply -f 02-break.yaml
# NOW: attempt to diagnose using the runbook before reading the solution
kubectl apply -f 03-solution.yaml
```

---

## The Networking Debugging Decision Tree

```
Traffic is failing
        │
        ▼
Does DNS resolve?
    Yes ────────────────────────────────────────────────────┐
    No                                                      │
     │                                                      ▼
     ▼                                              Can you reach the pod IP directly?
  Check CoreDNS pods running?                           Yes ─────────────────────────┐
  Check kube-dns service endpoints                      No                           │
  Check Corefile upstream                                │                           ▼
  Check NetworkPolicy (port 53 egress blocked?)         ▼                    Check Service:
                                                 Check CNI:                   - selector labels
                                                 - CNI pods running           - targetPort number
                                                 - ip route on node           - endpoints exist
                                                 - NetworkPolicy              - iptables DNAT
                                                 - iptables                   │
                                                                              ▼
                                                                       Check Ingress:
                                                                       - backend svc name
                                                                       - annotations
                                                                       - controller logs
```
