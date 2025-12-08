# RHOAI Metrics Dashboard Role

Ansible role to deploy RHOAI User Workload Metrics and Grafana dashboards for monitoring Single Serving Models (vLLM, OpenVino) on OpenShift AI.

## Overview

This role enables comprehensive monitoring of AI model serving workloads by:
- Enabling OpenShift User Workload Monitoring
- Deploying Grafana dashboards for vLLM and OpenVino models
- Configuring GPU metrics collection (NVIDIA DCGM Exporter)
- Creating ServiceMonitors for InferenceServices
- Auto-discovering deployed models

## Prerequisites

- OpenShift 4.10 or later
- OpenShift AI 2.10+ with KServe installed
- `oc` CLI configured with cluster-admin access
- Ansible 2.9+ with `kubernetes.core` collection
- `git` command-line tool
- Python packages: `kubernetes`, `openshift`, `gitpython`

**Optional:**
- NVIDIA GPU Operator (for GPU metrics)
- Grafana Operator (auto-installed if not present)

**Install Python dependencies:**
```bash
pip install ansible kubernetes openshift gitpython
```

## Role Variables

### Required Variables

```yaml
ocp4_workload_rhoai_metrics_namespace: "llm-hosting"  # Model serving namespace
```

### Repository Configuration

```yaml
ocp4_workload_rhoai_metrics_uwm_repo: "https://github.com/rh-aiservices-bu/rhoai-uwm.git"
ocp4_workload_rhoai_metrics_uwm_version: "main"
ocp4_workload_rhoai_metrics_uwm_overlay: "overlays/grafana-uwm-user-app"
```

### Monitoring Configuration

```yaml
# Enable user workload monitoring
ocp4_workload_rhoai_metrics_enable_uwm: true
ocp4_workload_rhoai_metrics_uwm_retention: "7d"

# Enable KServe monitoring
ocp4_workload_rhoai_metrics_enable_kserve: true
ocp4_workload_rhoai_metrics_kserve_namespace: "redhat-ods-applications"

# Scrape configuration
ocp4_workload_rhoai_metrics_scrape_interval: "30s"
ocp4_workload_rhoai_metrics_scrape_timeout: "10s"
```

### GPU Monitoring

```yaml
# Enable GPU metrics (requires GPU Operator)
ocp4_workload_rhoai_metrics_enable_gpu: true
ocp4_workload_rhoai_metrics_gpu_operator_namespace: "nvidia-gpu-operator"
ocp4_workload_rhoai_metrics_dcgm_enabled: true
```

### Grafana Configuration

```yaml
# Install Grafana Operator
ocp4_workload_rhoai_metrics_install_grafana_operator: true
ocp4_workload_rhoai_metrics_grafana_operator_channel: "v5"

# Deploy Grafana instance
ocp4_workload_rhoai_metrics_deploy_grafana: true
ocp4_workload_rhoai_metrics_grafana_instance_name: "rhoai-grafana"
```

### Model Discovery

```yaml
# Auto-discover all models (default)
ocp4_workload_rhoai_metrics_models: []

# Or specify specific models
ocp4_workload_rhoai_metrics_models:
  - llama-3-2-1b-fp8
  - granite-4-0-h-tiny
  - codellama-7b-instruct

# Runtime types to monitor
ocp4_workload_rhoai_metrics_runtimes:
  - vllm
  - openvino
```

## Example Playbook

### Basic Usage

```yaml
---
- name: Deploy RHOAI Metrics Dashboard
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Deploy RHOAI metrics monitoring
      ansible.builtin.include_role:
        name: rhpds.litemaas.ocp4_workload_rhoai_metrics
      vars:
        ocp4_workload_rhoai_metrics_namespace: "llm-hosting"
```

### Advanced Configuration

```yaml
---
- name: Deploy RHOAI Metrics with Custom Configuration
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Deploy RHOAI metrics monitoring
      ansible.builtin.include_role:
        name: rhpds.litemaas.ocp4_workload_rhoai_metrics
      vars:
        ocp4_workload_rhoai_metrics_namespace: "llm-hosting"
        ocp4_workload_rhoai_metrics_enable_gpu: true
        ocp4_workload_rhoai_metrics_uwm_retention: "14d"
        ocp4_workload_rhoai_metrics_scrape_interval: "15s"
        ocp4_workload_rhoai_metrics_models:
          - llama-3-2-1b-fp8
          - granite-4-0-h-tiny
        ocp4_workload_rhoai_metrics_runtimes:
          - vllm
```

### Remove RHOAI Metrics

```yaml
---
- name: Remove RHOAI Metrics Dashboard
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Remove RHOAI metrics monitoring
      ansible.builtin.include_role:
        name: rhpds.litemaas.ocp4_workload_rhoai_metrics
        tasks_from: remove_workload
      vars:
        ocp4_workload_rhoai_metrics_namespace: "llm-hosting"
        ocp4_workload_rhoai_metrics_remove: true
```

## What Gets Deployed

### OpenShift User Workload Monitoring
- Enables `enableUserWorkload` in cluster monitoring
- Configures Prometheus retention (default: 7 days)
- Deploys user workload Prometheus pods

### Grafana Dashboards
- **vLLM Model Metrics Dashboard** - Model-specific metrics (tokens, latency, throughput)
- **vLLM Service Performance Dashboard** - Service-level performance metrics
- **OpenVino Model Metrics Dashboard** - OpenVino model metrics
- **OpenVino Service Performance Dashboard** - OpenVino service metrics

### ServiceMonitors
- Creates ServiceMonitor for each vLLM InferenceService
- Creates ServiceMonitor for each OpenVino InferenceService
- Creates ServiceMonitor for NVIDIA DCGM Exporter (GPU metrics)

### Auto-Discovery
- Automatically discovers InferenceServices in the specified namespace
- Creates monitoring configuration based on runtime type (vLLM vs OpenVino)

## Accessing Grafana

After deployment, Grafana is accessible via:

```bash
# Get Grafana route
oc get route rhoai-grafana-route -n llm-hosting

# Open in browser
https://<grafana-route-hostname>
```

**Default credentials:**
- Login via OpenShift OAuth
- Uses your OpenShift user credentials

## Available Dashboards

Once logged into Grafana:

1. **Home** → **Dashboards**
2. Look for:
   - `vLLM - Model Metrics`
   - `vLLM - Service Performance`
   - `OpenVino - Model Metrics`
   - `OpenVino - Service Performance`

## Monitoring Features

### vLLM Metrics
- Request rate and latency
- Token generation metrics
- KV cache utilization
- Batch processing statistics
- GPU memory usage per model

### OpenVino Metrics
- Inference request counts
- Model inference latency
- Queue depths
- CPU/Memory utilization

### GPU Metrics (if enabled)
- GPU utilization percentage
- GPU memory usage
- Temperature and power consumption
- CUDA errors and ECC errors

## Troubleshooting

### User Workload Monitoring Not Starting

```bash
# Check monitoring pods
oc get pods -n openshift-user-workload-monitoring

# Check config
oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml
```

### Grafana Not Accessible

```bash
# Check Grafana pod
oc get pods -n llm-hosting -l app=grafana

# Check route
oc get route -n llm-hosting | grep grafana

# Check logs
oc logs -n llm-hosting deployment/rhoai-grafana
```

### No Metrics Showing

```bash
# Check ServiceMonitors
oc get servicemonitor -n llm-hosting

# Check if Prometheus can scrape targets
# Access Prometheus UI and check Targets page

# Verify model is exposing metrics
oc exec -n llm-hosting <model-pod> -- curl localhost:8080/metrics
```

### GPU Metrics Not Showing

```bash
# Check GPU Operator namespace
oc get pods -n nvidia-gpu-operator

# Check DCGM Exporter
oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter

# Check DCGM metrics endpoint
oc exec -n nvidia-gpu-operator <dcgm-pod> -- curl localhost:9400/metrics
```

## Integration with LiteMaaS

This role integrates seamlessly with LiteMaaS deployments:

```yaml
---
- name: Deploy LiteMaaS with Metrics
  hosts: localhost

  tasks:
    # Deploy LiteMaaS
    - name: Deploy LiteMaaS
      ansible.builtin.include_role:
        name: rhpds.litemaas.ocp4_workload_litemaas
      vars:
        ocp4_workload_litemaas_namespace: "litellm-prod"

    # Deploy metrics monitoring
    - name: Deploy RHOAI Metrics
      ansible.builtin.include_role:
        name: rhpds.litemaas.ocp4_workload_rhoai_metrics
      vars:
        ocp4_workload_rhoai_metrics_namespace: "llm-hosting"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  OpenShift Cluster                          │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Namespace: llm-hosting                            │    │
│  │                                                     │    │
│  │  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ vLLM Model   │  │ OpenVino     │               │    │
│  │  │ (Port 8080)  │  │ Model        │               │    │
│  │  │ /metrics     │  │ (Port 8080)  │               │    │
│  │  └──────┬───────┘  └──────┬───────┘               │    │
│  │         │                  │                        │    │
│  │    ┌────▼──────────────────▼────┐                  │    │
│  │    │    ServiceMonitors          │                  │    │
│  │    │    (30s scrape)             │                  │    │
│  │    └────┬────────────────────────┘                  │    │
│  │         │                                           │    │
│  │    ┌────▼────────────┐                             │    │
│  │    │   Grafana       │                             │    │
│  │    │   Dashboards    │◄────── User Access          │    │
│  │    └─────────────────┘        (via Route/OAuth)    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Namespace: openshift-user-workload-monitoring      │   │
│  │                                                      │   │
│  │  ┌──────────────────┐                               │   │
│  │  │   Prometheus     │◄──── Scrapes metrics          │   │
│  │  │   (7d retention) │                               │   │
│  │  └──────────────────┘                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Namespace: nvidia-gpu-operator                     │   │
│  │                                                      │   │
│  │  ┌──────────────────┐                               │   │
│  │  │  DCGM Exporter   │◄──── GPU metrics              │   │
│  │  │  (Port 9400)     │                               │   │
│  │  └──────────────────┘                               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Managing ServiceMonitors and Admin Users

### Adding New ServiceMonitors

ServiceMonitors are automatically created for InferenceServices based on their `modelFormat.name` field. To manually add a ServiceMonitor for a new model:

**Option 1: Using the helper script**

```bash
cd roles/ocp4_workload_rhoai_metrics
./scripts/add-servicemonitor.sh <model-name> <namespace>

# Example:
./scripts/add-servicemonitor.sh my-new-model llm-hosting
```

**Option 2: Manual YAML**

```bash
oc apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <model-name>-monitor
  namespace: llm-hosting
  labels:
    app: vllm
spec:
  endpoints:
    - interval: 30s
      port: http
      path: /metrics
      scheme: http
      timeout: 10s
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: <model-name>
EOF
```

### Adding New Admin Users to Grafana

**Option 1: Using the helper script**

```bash
cd roles/ocp4_workload_rhoai_metrics
./scripts/add-grafana-admin.sh <email> <namespace>

# Example:
./scripts/add-grafana-admin.sh newuser@redhat.com llm-hosting
```

**Option 2: Manual update**

Edit the RoleBinding:

```bash
oc edit rolebinding grafana-admin -n llm-hosting
```

Add new user to the subjects list:

```yaml
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: newuser@redhat.com
```

**Option 3: Update role defaults**

Edit `roles/ocp4_workload_rhoai_metrics/defaults/main.yml` and add:

```yaml
ocp4_workload_rhoai_metrics_grafana_admins:
  - psrivast@redhat.com
  - newuser@redhat.com
```

Then redeploy the role.

### Removing Admin Access

```bash
# Remove specific user
oc patch rolebinding grafana-admin -n llm-hosting --type=json \
  -p='[{"op": "remove", "path": "/subjects/0"}]'

# Or edit manually
oc edit rolebinding grafana-admin -n llm-hosting
```

## References

- [RHOAI UWM Repository](https://github.com/rh-aiservices-bu/rhoai-uwm)
- [OpenShift Monitoring Documentation](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
- [GPU Monitoring with DCGM](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/dcgm-exporter.html)
- [KServe Metrics](https://kserve.github.io/website/latest/modelserving/detect/explainer/explainer/)

## License

Apache License 2.0

## Author

Red Hat Demo Platform Development Team
