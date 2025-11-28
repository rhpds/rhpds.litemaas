# LiteMaaS Monitoring Role

Standalone Ansible role to deploy comprehensive monitoring for existing LiteMaaS (LiteLLM) deployments on OpenShift.

## Features

- **ServiceMonitor** - Prometheus Operator CRD for metrics scraping
- **PrometheusRules** - Alert definitions for critical and warning conditions
- **Grafana Operator** - Automated Grafana instance deployment
- **Grafana Dashboards** - Application and infrastructure metrics
- **Icinga Integration** - Optional alert routing via AlertmanagerConfig
- **OpenShift User Workload Monitoring** - Auto-enable if not configured

## Prerequisites

1. **Existing LiteMaaS deployment** - This role does NOT modify LiteLLM deployment
2. **Prometheus metrics enabled** in LiteLLM:
   ```yaml
   env:
     - name: LITELLM_ENABLE_METRICS
       value: "true"
     - name: PROMETHEUS_MULTIPROC_DIR
       value: "/tmp/metrics"
   ```
3. **OpenShift cluster** with cluster-admin or appropriate RBAC permissions
4. **oc CLI** logged into the cluster

## Quick Start

### Using the standalone script (recommended)

```bash
# Deploy monitoring
./setup-monitoring.sh litellm-rhpds

# Remove monitoring
./setup-monitoring.sh litellm-rhpds --remove

# With Icinga integration
./setup-monitoring.sh litellm-rhpds --icinga \
  --icinga-url https://icinga.example.com/v1/events \
  --icinga-user prometheus \
  --icinga-pass secret
```

### Using Ansible playbook directly

```bash
# Deploy monitoring
ansible-playbook playbooks/setup_litemaas_monitoring.yml \
  -e ocp4_workload_litemaas_monitoring_namespace=litellm-rhpds

# Remove monitoring
ansible-playbook playbooks/setup_litemaas_monitoring.yml \
  -e ocp4_workload_litemaas_monitoring_namespace=litellm-rhpds \
  -e ocp4_workload_litemaas_monitoring_remove=true
```

## What Gets Deployed

### 1. ServiceMonitor

Prometheus Operator CRD that configures metrics scraping:

- **Scrapes**: LiteLLM service `/metrics` endpoint
- **Interval**: 30s (configurable)
- **Labels**: Adds namespace, pod, service labels

### 2. PrometheusRules

Alert definitions for LiteLLM monitoring:

**Critical Alerts:**
- High error rate (>5% for 5 minutes)
- High latency P99 (>10s for 5 minutes)
- Service down (unreachable for 2 minutes)
- Database connection pool exhausted (>95% for 5 minutes)

**Warning Alerts:**
- Elevated error rate (>1% for 10 minutes)
- Increased latency P95 (>5s for 10 minutes)
- High token consumption (>10000 tokens/sec for 10 minutes)
- Cache hit rate drop (<50% for 10 minutes)

### 3. Grafana Operator + Instance

- Installs Grafana Operator via OLM
- Deploys Grafana instance with Prometheus datasource
- Creates route for web access
- Configures RBAC for cluster monitoring access

### 4. Grafana Dashboards

**Application Metrics Dashboard:**
- Request rate by model
- Request latency (p50, p95, p99)
- Token consumption (input + output)
- Error rate by status code
- Active requests
- Cache hit rate

**Infrastructure Metrics Dashboard:**
- Pod CPU usage
- Pod memory usage
- PostgreSQL connection pool
- Network I/O
- Pod restarts
- Storage usage (PVC)
- Pod status table

### 5. AlertmanagerConfig (Optional - Icinga)

Routes alerts to Icinga via webhook when enabled:

- Configurable severity routing (critical, warning)
- Basic auth credentials
- Send resolved notifications

## Configuration Variables

### Required

```yaml
ocp4_workload_litemaas_monitoring_namespace: "litellm-rhpds"  # Target namespace
```

### ServiceMonitor

```yaml
ocp4_workload_litemaas_monitoring_scrape_interval: "30s"
ocp4_workload_litemaas_monitoring_scrape_timeout: "10s"
ocp4_workload_litemaas_monitoring_metrics_port: 4000
ocp4_workload_litemaas_monitoring_metrics_path: "/metrics"
```

### Grafana Operator

```yaml
ocp4_workload_litemaas_monitoring_deploy_grafana: true
ocp4_workload_litemaas_monitoring_install_grafana_operator: true
ocp4_workload_litemaas_monitoring_grafana_operator_namespace: "grafana-operator"
ocp4_workload_litemaas_monitoring_grafana_operator_channel: "v5"
ocp4_workload_litemaas_monitoring_deploy_grafana_instance: true
ocp4_workload_litemaas_monitoring_grafana_instance_name: "litemaas-grafana"
```

### Alerts

```yaml
ocp4_workload_litemaas_monitoring_deploy_alerts: true

# Critical thresholds
ocp4_workload_litemaas_monitoring_alert_error_rate_critical: 0.05  # 5%
ocp4_workload_litemaas_monitoring_alert_latency_p99_critical: 10  # seconds

# Warning thresholds
ocp4_workload_litemaas_monitoring_alert_error_rate_warning: 0.01  # 1%
ocp4_workload_litemaas_monitoring_alert_latency_p95_warning: 5  # seconds

# Notification channels
ocp4_workload_litemaas_monitoring_alert_email: ""
ocp4_workload_litemaas_monitoring_alert_slack_webhook: ""
```

### Icinga Integration

```yaml
ocp4_workload_litemaas_monitoring_icinga_enabled: false
ocp4_workload_litemaas_monitoring_icinga_api_url: ""  # https://icinga.example.com/v1/events
ocp4_workload_litemaas_monitoring_icinga_api_username: ""
ocp4_workload_litemaas_monitoring_icinga_api_password: ""
ocp4_workload_litemaas_monitoring_icinga_send_critical: true
ocp4_workload_litemaas_monitoring_icinga_send_warning: false
```

## Verification

### 1. Check ServiceMonitor

```bash
# List ServiceMonitors
oc get servicemonitors -n litellm-rhpds

# Describe ServiceMonitor
oc describe servicemonitor litellm -n litellm-rhpds
```

### 2. Check PrometheusRules

```bash
# List PrometheusRules
oc get prometheusrules -n litellm-rhpds

# Describe PrometheusRule
oc describe prometheusrule litellm-alerts -n litellm-rhpds
```

### 3. Test Metrics Endpoint

```bash
# Port-forward to LiteLLM service
oc port-forward -n litellm-rhpds svc/litellm 4000:4000

# Check metrics (in another terminal)
curl http://localhost:4000/metrics
```

### 4. Query Prometheus

```bash
# Port-forward to Prometheus
oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090

# Query metrics (in browser)
http://localhost:9090/graph

# Example queries:
rate(litellm_request_total[5m])
histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m]))
litellm_tokens_total
```

### 5. Access Grafana

```bash
# Get Grafana route
oc get route grafana -n litellm-rhpds

# Open in browser
https://grafana-litellm-rhpds.apps.cluster.com
```

## Removal

### Using script

```bash
./setup-monitoring.sh litellm-rhpds --remove
```

### Using playbook

```bash
ansible-playbook playbooks/setup_litemaas_monitoring.yml \
  -e ocp4_workload_litemaas_monitoring_namespace=litellm-rhpds \
  -e ocp4_workload_litemaas_monitoring_remove=true
```

### What gets removed

- ServiceMonitor: `litellm`
- PrometheusRule: `litellm-alerts`
- AlertmanagerConfig: `litemaas-icinga` (if existed)
- Grafana instance and dashboards
- Grafana ServiceAccount and ClusterRoleBinding

### What does NOT get removed

- **Grafana Operator** - May be shared across deployments
- **User Workload Monitoring** - Cluster-wide setting

To completely remove Grafana Operator:

```bash
oc delete subscription grafana-operator -n grafana-operator
oc delete csv -n grafana-operator -l operators.coreos.com/grafana-operator.grafana-operator
```

## Troubleshooting

### ServiceMonitor not scraping

**Problem**: Metrics not showing in Prometheus

**Check:**

1. Verify LiteLLM metrics are enabled:
   ```bash
   oc get deployment litellm -n litellm-rhpds -o yaml | grep LITELLM_ENABLE_METRICS
   ```

2. Test metrics endpoint manually:
   ```bash
   oc port-forward -n litellm-rhpds svc/litellm 4000:4000
   curl http://localhost:4000/metrics
   ```

3. Check ServiceMonitor targets in Prometheus:
   - Port-forward to Prometheus: `oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090`
   - Browse to: http://localhost:9090/targets
   - Look for `litellm` target

### Grafana Operator installation fails

**Problem**: Grafana Operator pod not starting

**Check:**

1. Verify OperatorHub connectivity:
   ```bash
   oc get packagemanifests | grep grafana
   ```

2. Check Subscription status:
   ```bash
   oc get subscription grafana-operator -n grafana-operator
   oc describe subscription grafana-operator -n grafana-operator
   ```

3. Check CSV (ClusterServiceVersion):
   ```bash
   oc get csv -n grafana-operator
   ```

### Alerts not firing

**Problem**: PrometheusRule created but alerts not showing

**Check:**

1. Verify PrometheusRule syntax:
   ```bash
   oc get prometheusrule litellm-alerts -n litellm-rhpds -o yaml
   ```

2. Check if metrics exist:
   ```bash
   # Port-forward to Prometheus and query
   litellm_request_total
   ```

3. Check AlertManager:
   ```bash
   oc get alertmanagers -n openshift-user-workload-monitoring
   ```

### Icinga integration not working

**Problem**: Alerts not reaching Icinga

**Check:**

1. Verify AlertmanagerConfig created:
   ```bash
   oc get alertmanagerconfig litemaas-icinga -n litellm-rhpds
   ```

2. Check credentials secret:
   ```bash
   oc get secret icinga-credentials -n litellm-rhpds
   ```

3. Test Icinga API manually:
   ```bash
   curl -X POST https://icinga.example.com/v1/events \
     -u prometheus:secret \
     -H "Content-Type: application/json" \
     -d '{"test": "alert"}'
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ OpenShift Cluster                                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Namespace: litellm-rhpds                             │  │
│  │                                                      │  │
│  │  ┌────────────┐        ┌──────────────────┐         │  │
│  │  │  LiteLLM   │───────▶│  ServiceMonitor  │         │  │
│  │  │  Service   │        │   (litellm)      │         │  │
│  │  │ :4000/     │        └─────────┬────────┘         │  │
│  │  │  metrics   │                  │                  │  │
│  │  └────────────┘                  │                  │  │
│  │                                  │                  │  │
│  │  ┌────────────────┐              │                  │  │
│  │  │ PrometheusRule │              │                  │  │
│  │  │ (litellm-alerts│              │                  │  │
│  │  └────────────────┘              │                  │  │
│  │                                  │                  │  │
│  │  ┌────────────────┐              │                  │  │
│  │  │    Grafana     │              │                  │  │
│  │  │   Instance     │◀─────────────┘                  │  │
│  │  │  + Dashboards  │                                 │  │
│  │  └────────────────┘                                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Namespace: openshift-user-workload-monitoring        │  │
│  │                                                      │  │
│  │  ┌──────────────┐         ┌──────────────┐          │  │
│  │  │  Prometheus  │────────▶│ AlertManager │          │  │
│  │  │ User Workload│         │              │          │  │
│  │  └──────────────┘         └──────┬───────┘          │  │
│  │                                  │                  │  │
│  └──────────────────────────────────┼──────────────────┘  │
│                                     │                     │
│  ┌──────────────────────────────────┼──────────────────┐  │
│  │ Namespace: grafana-operator      │                  │  │
│  │                                  │                  │  │
│  │  ┌───────────────────┐           │                  │  │
│  │  │ Grafana Operator  │           │                  │  │
│  │  │   (OLM managed)   │           │                  │  │
│  │  └───────────────────┘           │                  │  │
│  └──────────────────────────────────┼──────────────────┘  │
│                                     │                     │
└─────────────────────────────────────┼─────────────────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │   Icinga     │
                              │   (optional) │
                              └──────────────┘
```

## License

Apache-2.0

## Author

Prakhar Srivastava (psrivast@redhat.com)
Red Hat - Technical Marketing
