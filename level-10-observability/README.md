# Level 10: Observability Stack

*"You cannot fix what you cannot see."*

**Time estimate: 20-25 hours**

---

## Labs

| Lab | Scenario | Core Concepts |
|-----|----------|---------------|
| [10.1 Stack Setup](labs/lab-10.1-stack-setup/) | Deploy Prometheus + Grafana + Loki | kube-prometheus-stack Helm chart, ServiceMonitor, PodMonitor |
| [10.2 PromQL](labs/lab-10.2-promql/) | The 25 queries every SRE needs | rate(), histogram_quantile(), topk(), deriv() |
| [10.3 Alerting](labs/lab-10.3-alerting/) | Write and debug alert rules | PrometheusRule, inhibition, routing, dead man's switch |
| [10.4 Tracing](labs/lab-10.4-tracing/) | Find the slow span in a distributed trace | OpenTelemetry Collector, Jaeger/Tempo, trace correlation |

---

## Key Files

- **[promql-reference.md](labs/lab-10.2-promql/promql-reference.md)** — 25 copy-paste PromQL queries
- **[alert-rules.yaml](labs/lab-10.3-alerting/alert-rules.yaml)** — Production alert rules with annotations
