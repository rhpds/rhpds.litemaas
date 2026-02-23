# LiteMaaS High Availability Deployment

LiteMaaS deploys exclusively in High Availability (HA) mode with multiple replicas, Redis caching, and PostgreSQL 16.

## Architecture

```
                    ┌─────────────────────────────────┐
                    │   OpenShift Routes (TLS)        │
                    │  litellm / litellm-frontend      │
                    └──────────────┬──────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                     ▼
     ┌──────────────┐    ┌──────────────┐     ┌──────────────┐
     │   LiteLLM    │    │   Backend    │     │   Frontend   │
     │  (3 replicas)│    │   API        │     │   Web UI     │
     └──────┬───────┘    └──────────────┘     └──────────────┘
            │
    ┌───────┴────────┐
    ▼                ▼
┌────────┐    ┌──────────────┐
│ Redis  │    │ PostgreSQL   │
│(Cache) │    │    16        │
└────────┘    └──────────────┘
```

## Quick Start

```bash
# Standard deployment (OAuth enabled by default)
ansible-playbook playbooks/deploy_litemaas_ha.yml

# With RHDP branding
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_branding_enabled=true

# Custom replicas and namespace
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_namespace=litellm-production \
  -e ocp4_workload_litemaas_ha_litellm_replicas=5
```

## Configuration Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_litellm_replicas` | `3` | Number of LiteLLM pod replicas |

### Redis Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_enable_redis` | `true` | Deploy Redis for caching |
| `ocp4_workload_litemaas_ha_redis_image` | `registry.redhat.io/rhel9/redis-7:latest` | Primary Redis image |
| `ocp4_workload_litemaas_ha_redis_image_fallback` | `quay.io/sclorg/redis-7-c9s:latest` | Fallback Redis image |
| `ocp4_workload_litemaas_ha_redis_memory_request` | `256Mi` | Redis memory request |
| `ocp4_workload_litemaas_ha_redis_memory_limit` | `512Mi` | Redis memory limit |
| `ocp4_workload_litemaas_ha_redis_cpu_request` | `200m` | Redis CPU request |
| `ocp4_workload_litemaas_ha_redis_cpu_limit` | `500m` | Redis CPU limit |

### PostgreSQL 16 Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_enable_postgres` | `true` | Deploy PostgreSQL 16 |
| `ocp4_workload_litemaas_ha_postgres_image` | `postgres:16` | PostgreSQL image |
| `ocp4_workload_litemaas_ha_postgres_db` | `litellm` | Database name |
| `ocp4_workload_litemaas_ha_postgres_user` | `litellm` | Database user |
| `ocp4_workload_litemaas_ha_postgres_password` | _auto-generated_ | Database password |
| `ocp4_workload_litemaas_ha_postgres_pvc_size` | `10Gi` | PVC size for data |
| `ocp4_workload_litemaas_ha_postgres_memory_request` | `512Mi` | PostgreSQL memory request |
| `ocp4_workload_litemaas_ha_postgres_memory_limit` | `2Gi` | PostgreSQL memory limit |
| `ocp4_workload_litemaas_ha_postgres_cpu_request` | `500m` | PostgreSQL CPU request |
| `ocp4_workload_litemaas_ha_postgres_cpu_limit` | `2000m` | PostgreSQL CPU limit |

### LiteLLM Resource Limits

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_litellm_memory_request` | `512Mi` | LiteLLM memory request |
| `ocp4_workload_litemaas_ha_litellm_memory_limit` | `2Gi` | LiteLLM memory limit |
| `ocp4_workload_litemaas_ha_litellm_cpu_request` | `500m` | LiteLLM CPU request |
| `ocp4_workload_litemaas_ha_litellm_cpu_limit` | `2000m` | LiteLLM CPU limit |

## Resource Sizing

### Standard Deployment (3 replicas)

```yaml
Total Resources:
- CPU Request: 2.4 cores
- Memory Request: 2.8Gi
- Storage: 10Gi

Components:
- LiteLLM (3 replicas): 1500m CPU, 1.5Gi RAM
- PostgreSQL: 500m CPU, 512Mi RAM
- Redis: 200m CPU, 256Mi RAM
- Backend: 100m CPU, 256Mi RAM
- Frontend: 100m CPU, 128Mi RAM
```

### Large Deployment (5+ replicas)

```yaml
Total Resources:
- CPU Request: 3.4+ cores
- Memory Request: 3.8+ Gi
- Storage: 10Gi

Components:
- LiteLLM (5 replicas): 2500m CPU, 2.5Gi RAM
- PostgreSQL: 500m CPU, 512Mi RAM
- Redis: 200m CPU, 256Mi RAM
- Backend: 100m CPU, 256Mi RAM
- Frontend: 100m CPU, 128Mi RAM
```

## Image Fallback Strategy

The deployment automatically handles image registry failures:

1. **Tries primary image first**
2. **Falls back to alternative** if primary is inaccessible
3. **Logs which image was used** for troubleshooting

## Deployment Order

1. **Namespace creation**
2. **PostgreSQL 16** - Secret, Service, StatefulSet with PVC, wait for ready
3. **Redis** - Service, Deployment, wait for ready
4. **LiteLLM (HA)** - Secret, Deployment (multiple replicas), Service, Route
5. **Backend** - Secret, Deployment, Service
6. **Frontend** - Deployment, Service, Route
7. **Branding** (if enabled) - ConfigMaps, sidecar proxy

## Verification

```bash
# Check all pods
oc get pods -n litemaas

# Expected output:
# litellm-xxxxx             1/1     Running   0    5m
# litellm-yyyyy             1/1     Running   0    5m
# litellm-zzzzz             1/1     Running   0    5m
# litellm-backend-xxxxx     1/1     Running   0    4m
# litellm-frontend-xxxxx    1/1     Running   0    3m  (or 2/2 with branding)
# litellm-postgres-0        1/1     Running   0    8m
# litellm-redis-xxxxx       1/1     Running   0    7m

# Check routes
oc get routes -n litemaas

# Test health
ROUTE=$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')
curl https://$ROUTE/health/livenessz
```

## Removal

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_remove=true
```

Or directly:
```bash
oc delete namespace litemaas
```

## AgnosticV Integration

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

ocp4_workload_litemaas_ha_litellm_replicas: 3
ocp4_workload_litemaas_oauth_enabled: true
ocp4_workload_litemaas_deploy_backend: true
ocp4_workload_litemaas_deploy_frontend: true
```
