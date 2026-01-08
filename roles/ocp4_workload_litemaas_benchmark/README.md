# ocp4_workload_litemaas_benchmark

Ansible role for running performance benchmarks against LiteMaaS deployments. Tests multi-turn conversation workloads to validate Time to First Token (TTFT) performance and prefix caching effectiveness.

## Purpose

- **Performance Validation**: Measure TTFT, throughput, and latency metrics
- **Prefix Caching Analysis**: Validate KV cache effectiveness across conversation turns
- **Load Testing**: Simulate realistic multi-user workloads
- **Pre-Event Validation**: Test capacity before workshops/demos
- **Model Comparison**: Benchmark different LLM models

## Features

- Multi-turn conversation simulation with realistic prompts
- Parallel request execution with random delays (simulates real users)
- Comprehensive metrics: TTFT (P50/P95/P99), speedup ratio, throughput
- Automatic result parsing and user.info integration
- Configurable load patterns and thresholds
- Uses multi-turn-benchmarking tool (https://github.com/rh-aiservices-bu/multi-turn-benchmarking)

## Requirements

- OpenShift cluster with namespace access
- `rhpds.litellm_virtual_keys` workload must run first (provides API endpoint and key)
- Kubernetes.core collection

## Role Variables

### Required Variables (auto-populated from virtual keys workload)

```yaml
# LiteMaaS connection (auto-populated)
ocp4_workload_litemaas_benchmark_url: "{{ lookup('agnosticd_user_data', 'litellm_api_base_url') }}"
ocp4_workload_litemaas_benchmark_key: "{{ lookup('agnosticd_user_data', 'litellm_virtual_key') }}"
```

### Benchmark Configuration

```yaml
# Enable/disable benchmark
ocp4_workload_litemaas_benchmark_enabled: true

# Namespace for benchmark Job
ocp4_workload_litemaas_benchmark_namespace: "{{ guid }}"

# Load configuration
ocp4_workload_litemaas_benchmark_conversations: 20      # Concurrent conversations (users)
ocp4_workload_litemaas_benchmark_turns: 10              # Follow-up questions per conversation
ocp4_workload_litemaas_benchmark_parallel_workers: 4    # Concurrent request workers
ocp4_workload_litemaas_benchmark_max_tokens: 500        # Max tokens per response

# Request timing (simulates real user behavior)
ocp4_workload_litemaas_benchmark_min_delay: 0.5         # Min seconds between requests
ocp4_workload_litemaas_benchmark_max_delay: 2.0         # Max seconds between requests

# Performance thresholds
ocp4_workload_litemaas_benchmark_ttft_p95_threshold_ms: 500   # P95 TTFT threshold
ocp4_workload_litemaas_benchmark_speedup_threshold: 2.0       # Cache speedup threshold

# Container image
ocp4_workload_litemaas_benchmark_image: quay.io/hayesphilip/multi-turn-benchmark:0.0.1
```

## Dependencies

This role depends on `rhpds.litellm_virtual_keys` workload running first to provide:
- LiteMaaS API endpoint URL
- Virtual API key

## Example Usage

### In AgnosticV Catalog (common.yaml)

```yaml
# Workloads
workloads:
  - rhpds.litellm_virtual_keys.ocp4_workload_litellm_virtual_keys
  - rhpds.litemaas.ocp4_workload_litemaas_benchmark  # ← Add this

# Configure benchmark
ocp4_workload_litemaas_benchmark_enabled: true
ocp4_workload_litemaas_benchmark_conversations: 50
ocp4_workload_litemaas_benchmark_turns: 10
```

### As Catalog Parameter

```yaml
# In catalog parameters
- name: run_benchmark
  formLabel: Run Performance Benchmark
  formGroup: Benchmark Configuration
  openAPIV3Schema:
    type: boolean
    default: true

- name: benchmark_conversations
  formLabel: Concurrent Conversations
  formGroup: Benchmark Configuration
  openAPIV3Schema:
    type: integer
    default: 20

# In variables
ocp4_workload_litemaas_benchmark_enabled: "{{ run_benchmark | default(true) }}"
ocp4_workload_litemaas_benchmark_conversations: "{{ benchmark_conversations | default(20) }}"
```

### Standalone Playbook

```yaml
---
- name: Run LiteMaaS benchmark
  hosts: localhost
  gather_facts: false
  vars:
    ocp4_workload_litemaas_benchmark_url: "https://litemaas.example.com/v1"
    ocp4_workload_litemaas_benchmark_key: "sk-abc123..."
    ocp4_workload_litemaas_benchmark_conversations: 30
  roles:
    - rhpds.litemaas.ocp4_workload_litemaas_benchmark
```

## Output

### User Info Data

The role saves results to `agnosticd_user_info` data:

```yaml
litemaas_benchmark_p50_ms: "92.09"
litemaas_benchmark_p95_ms: "271.60"
litemaas_benchmark_p99_ms: "674.21"
litemaas_benchmark_mean_ms: "120.98"
litemaas_benchmark_speedup_ratio: "3.84"
litemaas_benchmark_status: "PASS ✓"
litemaas_benchmark_cache_status: "EXCELLENT ✓"
litemaas_benchmark_total_requests: "110"
litemaas_benchmark_requests_per_second: "0.45"
```

### User Info Message

Example output shown to users:

```
════════════════════════════════════════════════════════════════
LiteMaaS Benchmark Results
════════════════════════════════════════════════════════════════

Time to First Token (TTFT):
  • Mean:           120.98 ms
  • P50 (Median):   92.09 ms
  • P95:            271.60 ms
  • P99:            674.21 ms

Cache Performance:
  • Speedup Ratio:  3.84x
  • Status:         EXCELLENT ✓

Load Testing Results:
  • Total Time:     242.75 seconds
  • Total Requests: 110
  • Requests/sec:   0.45

Overall Status: PASS ✓
════════════════════════════════════════════════════════════════
```

## Performance Interpretation

### TTFT Thresholds

- **P95 < 500ms**: Excellent user experience ✓
- **P95 < 1000ms**: Good user experience
- **P95 > 1000ms**: May need optimization ✗

### Cache Speedup

- **> 3x**: Excellent prefix caching ✓
- **> 2x**: Good prefix caching
- **< 2x**: Poor cache effectiveness ✗

The speedup ratio compares first turn TTFT (full document processing) vs later turns (cached prefix).

## Cleanup on Destroy

The role automatically cleans up resources when the catalog item is destroyed.

### What Gets Removed

- Benchmark Job (`litemaas-benchmark`)
- Benchmark Pods (with label `app=litemaas-benchmark`)
- Namespace (only if different from guid namespace)

### Remove Workload Configuration

```yaml
# In AgnosticV catalog common.yaml
remove_workloads:
  - rhpds.litemaas.ocp4_workload_litemaas_benchmark
  - rhpds.litellm_virtual_keys.ocp4_workload_litellm_virtual_keys
```

### Namespace Cleanup Behavior

**Shared namespace** (namespace = guid):
- Job and pods deleted
- Namespace preserved (shared with other resources)

**Dedicated namespace** (namespace != guid):
- Job and pods deleted
- Namespace deleted

### Manual Cleanup

If needed, clean up manually:

```bash
# Delete just the Job
oc delete job litemaas-benchmark -n <namespace>

# Delete all benchmark resources
oc delete all -l app=litemaas-benchmark -n <namespace>

# Delete entire namespace (if dedicated)
oc delete namespace <namespace>
```

## Troubleshooting

### View Live Logs

```bash
oc logs -n <namespace> -l app=litemaas-benchmark -f
```

### Check Job Status

```bash
oc get job litemaas-benchmark -n <namespace>
```

### Common Issues

1. **Benchmark fails immediately**
   - Check LiteMaaS endpoint is reachable
   - Verify API key is valid
   - Ensure virtual keys workload ran successfully

2. **Context length exceeded**
   - Reduce `ocp4_workload_litemaas_benchmark_max_tokens`
   - Reduce `ocp4_workload_litemaas_benchmark_turns`

3. **Timeout**
   - Increase `ocp4_workload_litemaas_benchmark_timeout_seconds`
   - Reduce conversation count for faster completion

## Use Cases

### Pre-RH1 Validation

```yaml
# Test capacity before Red Hat One event
ocp4_workload_litemaas_benchmark_conversations: 100  # Expected attendees
ocp4_workload_litemaas_benchmark_turns: 10
```

### Model Comparison

Run benchmarks with different models to compare performance:

```yaml
# Order 1: Test Granite 3.2 8B
ocp4_workload_litellm_virtual_keys_models: ['granite-3-2-8b-instruct']

# Order 2: Test Llama Scout 17B
ocp4_workload_litellm_virtual_keys_models: ['llama-scout-17b']

# Compare P95 TTFT and speedup ratios
```

### Continuous Testing

```yaml
# Light continuous load
ocp4_workload_litemaas_benchmark_conversations: 10
ocp4_workload_litemaas_benchmark_turns: 5
ocp4_workload_litemaas_benchmark_min_delay: 1.0
ocp4_workload_litemaas_benchmark_max_delay: 5.0
```

## License

Apache-2.0

## Author

Prakhar Srivastava <psrivast@redhat.com>
