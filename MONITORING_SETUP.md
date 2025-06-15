# Yield Optimizer Monitoring Setup

This guide covers the complete monitoring setup for the Yield Optimizer using Prometheus, Grafana, and AlertManager.

## Overview

The monitoring stack provides:
- **Metrics Collection**: Prometheus scrapes custom metrics from the yield-optimizer
- **Visualization**: Grafana dashboards for real-time monitoring
- **Alerting**: AlertManager for critical notifications
- **Custom Metrics**: Application-specific metrics for yield optimization

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│ Yield Optimizer │────►│  Prometheus  │────►│   Grafana   │
│    Monitor      │     │              │     │             │
└─────────────────┘     └──────────────┘     └─────────────┘
         │                      │
         │                      ▼
         │              ┌──────────────┐
         └─────────────►│ AlertManager │
                        └──────────────┘
```

## 1. Deploy Prometheus Stack

### Using Helm (Recommended)

```bash
# Add prometheus-community helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/kube-prometheus-stack-values.yaml \
  --wait
```

### Verify Installation

```bash
# Check all monitoring components
kubectl get all -n monitoring

# Check prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Access: http://localhost:9090

# Check grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Access: http://localhost:3000 (admin/admin)

# Check alertmanager
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093
# Access: http://localhost:9093
```

## 2. Configure Service Monitoring

### Deploy Prometheus Rules

```bash
# Apply custom alerting rules
kubectl apply -f k8s/monitoring/prometheus-rules.yaml

# Verify rules are loaded
kubectl get prometheusrule -n yield-optimizer
```

### Update Helm Values for ServiceMonitor

Ensure your `values.yaml` includes:

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  path: /metrics
  labels:
    app.kubernetes.io/part-of: yield-optimizer
```

## 3. Custom Metrics

The monitor service exposes the following custom metrics:

### Position Metrics
- `yield_optimizer_positions_total`: Total active positions by vault
- `yield_optimizer_position_value_usd`: Position value in USD

### APY Metrics
- `yield_optimizer_apy_current`: Current APY per vault
- `yield_optimizer_apy_historical`: Historical APY distribution

### Rebalancing Metrics
- `yield_optimizer_rebalances_total`: Total rebalances by status
- `yield_optimizer_rebalance_duration_seconds`: Rebalance duration
- `yield_optimizer_gas_used_total`: Gas usage by operation

### Error Tracking
- `yield_optimizer_errors_total`: Errors by type and operation

### System Metrics
- `yield_optimizer_database_connections_active`: Active DB connections
- `yield_optimizer_contract_calls_total`: Smart contract interactions
- `yield_optimizer_health_check_status`: Component health status

## 4. Grafana Dashboards

### Import Dashboard

```bash
# Apply dashboard ConfigMap
kubectl apply -f k8s/monitoring/grafana-dashboard-configmap.yaml

# Or import manually in Grafana UI:
# 1. Go to Dashboards → Import
# 2. Upload k8s/monitoring/yield-optimizer-dashboard.json
```

### Dashboard Panels

1. **Current APY by Vault**: Real-time APY tracking
2. **Total Active Positions**: Position count gauge
3. **Rebalances per Second**: Rebalance rate over time
4. **Error Rate by Type**: Error tracking and categorization
5. **HTTP Request Duration**: API performance metrics
6. **Resource Availability**: CPU/Memory usage

### Custom Dashboard Creation

Create new dashboards with these queries:

```promql
# Average APY across all vaults
avg(yield_optimizer_apy_current)

# Success rate of rebalances
sum(rate(yield_optimizer_rebalances_total{status="success"}[5m])) / 
sum(rate(yield_optimizer_rebalances_total[5m]))

# Position value by vault
sum(yield_optimizer_position_value_usd) by (vault)

# Error rate trend
rate(yield_optimizer_errors_total[5m])
```

## 5. Alerting Configuration

### Critical Alerts

1. **NoActivePositions**: No positions for 15 minutes
2. **HighRebalanceFailureRate**: >50% rebalances failing
3. **ContractInteractionErrors**: Smart contract failures
4. **MonitorServiceDown**: Service unavailable

### Alert Routing

Configure AlertManager receivers in `values.yaml`:

```yaml
alertmanager:
  config:
    receivers:
    - name: 'yield-optimizer-alerts'
      slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#yield-optimizer-alerts'
        title: 'Yield Optimizer Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

### Testing Alerts

```bash
# Trigger test alert
kubectl exec -it -n monitoring prometheus-stack-kube-prom-prometheus-0 -- \
  promtool tsdb create-blocks-from rules \
  --eval-interval=30s \
  /etc/prometheus/rules/prometheus-prometheus-stack-kube-prom-prometheus-rulefiles-0/*.yaml
```

## 6. Integration with Monitor Service

### Update monitor service to expose metrics

The `metrics.go` file provides all metric definitions. Integrate in your main service:

```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
    // Initialize metrics collector
    metricsCollector := NewMetricsCollector(monitor)
    
    // Expose metrics endpoint
    http.Handle("/metrics", promhttp.Handler())
    
    // Update metrics in your business logic
    metricsCollector.UpdatePositionMetrics(positions)
    metricsCollector.RecordRebalance(vault, success, duration)
}
```

### Metric Updates in Business Logic

```go
// After successful rebalance
metricsCollector.RecordRebalance("vault-1", true, time.Since(start).Seconds())

// On error
metricsCollector.RecordError("contract_interaction", "rebalance")

// Update APY
metricsCollector.UpdateAPYMetrics("vault-1", currentAPY)
```

## 7. Monitoring Best Practices

### Metric Naming
- Use consistent prefixes: `yield_optimizer_*`
- Include units in names: `_seconds`, `_total`, `_bytes`
- Use labels for dimensions

### Label Cardinality
- Keep label values bounded
- Avoid high-cardinality labels (user IDs, transaction hashes)
- Use recording rules for expensive queries

### Dashboard Design
- Group related metrics
- Use appropriate visualization types
- Set meaningful thresholds
- Include documentation links

### Alert Design
- Start with few, high-quality alerts
- Include runbook links in annotations
- Set appropriate severity levels
- Test alerts regularly

## 8. Troubleshooting

### Metrics Not Appearing

```bash
# Check if service is being scraped
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Go to http://localhost:9090/targets

# Check ServiceMonitor
kubectl get servicemonitor -n yield-optimizer -o yaml

# Test metrics endpoint directly
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080
curl http://localhost:8080/metrics
```

### Dashboard Not Loading

```bash
# Check ConfigMap
kubectl get configmap -n yield-optimizer yield-optimizer-dashboard

# Check Grafana logs
kubectl logs -n monitoring deployment/prometheus-stack-grafana

# Verify dashboard label
kubectl get configmap -n yield-optimizer -l grafana_dashboard=1
```

### Alerts Not Firing

```bash
# Check PrometheusRule
kubectl describe prometheusrule -n yield-optimizer yield-optimizer-rules

# Check Prometheus config
kubectl exec -it -n monitoring prometheus-stack-kube-prom-prometheus-0 -- cat /etc/prometheus/prometheus.yaml

# Test alert expression
# In Prometheus UI, evaluate the alert expression
```

## 9. Performance Optimization

### Metric Collection
- Use histograms for latency measurements
- Batch metric updates when possible
- Avoid metrics in hot paths

### Query Optimization
- Use recording rules for expensive queries
- Leverage PromQL functions efficiently
- Set appropriate retention periods

### Storage Management
- Configure appropriate retention
- Use remote storage for long-term data
- Monitor Prometheus disk usage

## 10. Security Considerations

### Access Control
- Enable authentication for Grafana
- Use RBAC for Prometheus access
- Secure AlertManager webhooks

### Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-access
  namespace: yield-optimizer
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: yield-optimizer
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - port: 8080
      protocol: TCP
```

## Next Steps

1. **Production Setup**
   - Configure persistent storage
   - Set up backup procedures
   - Implement retention policies

2. **Advanced Monitoring**
   - Add tracing with Jaeger
   - Implement SLO/SLI tracking
   - Create runbooks for alerts

3. **Integration**
   - Connect to incident management
   - Set up on-call rotations
   - Implement automated remediation