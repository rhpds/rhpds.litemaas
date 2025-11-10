# LiteMaaS High Availability Deployment

This guide covers deploying LiteMaaS in High Availability (HA) mode with multiple replicas, Redis caching, and PostgreSQL 16.

## Overview

The HA deployment includes:
- **Multiple LiteLLM replicas** (default: 2, configurable)
- **Redis cache** for session and response caching
- **PostgreSQL 16** for persistent data storage
- **Health probes** for readiness and liveness
- **Red Hat certified images** with fallback options

## Architecture

```
┌─────────────────────────────────────────┐
│         OpenShift Route (TLS)           │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│      LiteMaaS Service (ClusterIP)       │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌─────────────┐  ┌─────────────┐
│  LiteLLM    │  │  LiteLLM    │  (Replicas: 2+)
│  Pod 1      │  │  Pod 2      │
└──────┬──────┘  └──────┬──────┘
       │                │
       └────┬──────┬────┘
            │      │
    ┌───────▼──┐ ┌▼────────────┐
    │  Redis   │ │ PostgreSQL  │
    │  (Cache) │ │    16       │
    └──────────┘ └─────────────┘
```

## Quick Start

### Deploy with Default Settings

```bash
cd ~/work/code/rhpds.litemaas

# Build and install collection
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force

# Deploy in HA mode
ansible-playbook playbooks/deploy_litemaas_ha.yml
```

### Deploy with Custom Replicas

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_ha_litellm_replicas=3
```

### Deploy with Custom Namespace

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_namespace=litemaas-production \
  -e ocp4_workload_litemaas_ha_litellm_replicas=4
```

## Configuration Variables

### Core HA Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_enabled` | `false` | Enable HA deployment mode |
| `ocp4_workload_litemaas_ha_litellm_replicas` | `2` | Number of LiteLLM pod replicas |

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
| `ocp4_workload_litemaas_ha_postgres_image` | `registry.redhat.io/rhel9/postgresql-16:latest` | Primary PostgreSQL image |
| `ocp4_workload_litemaas_ha_postgres_image_fallback` | `quay.io/sclorg/postgresql-16-c9s:latest` | Fallback PostgreSQL image |
| `ocp4_workload_litemaas_ha_postgres_db` | `litemaas` | Database name |
| `ocp4_workload_litemaas_ha_postgres_user` | `litemaas` | Database user |
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

### Small HA Deployment (2 replicas)

```yaml
Total Resources:
- CPU Request: 1.9 cores
- Memory Request: 2.3Gi
- Storage: 10Gi

Components:
- LiteLLM (2 replicas): 1000m CPU, 1Gi RAM
- PostgreSQL: 500m CPU, 512Mi RAM
- Redis: 200m CPU, 256Mi RAM
```

### Medium HA Deployment (3 replicas)

```yaml
Total Resources:
- CPU Request: 2.4 cores
- Memory Request: 2.8Gi
- Storage: 10Gi

Components:
- LiteLLM (3 replicas): 1500m CPU, 1.5Gi RAM
- PostgreSQL: 500m CPU, 512Mi RAM
- Redis: 200m CPU, 256Mi RAM
```

### Large HA Deployment (4+ replicas)

```yaml
Total Resources:
- CPU Request: 2.9+ cores
- Memory Request: 3.3+ Gi
- Storage: 20Gi+

Components:
- LiteLLM (4 replicas): 2000m CPU, 2Gi RAM
- PostgreSQL: 500m CPU, 512Mi RAM
- Redis: 200m CPU, 256Mi RAM
```

## Image Fallback Strategy

The HA deployment automatically handles image registry failures:

1. **Tries Red Hat registry first** (`registry.redhat.io`)
2. **Falls back to Quay.io** if Red Hat registry is inaccessible
3. **Logs which image was used** for troubleshooting

### Example: PostgreSQL Image Selection

```yaml
Primary: registry.redhat.io/rhel9/postgresql-16:latest
Fallback: quay.io/sclorg/postgresql-16-c9s:latest
```

### Example: Redis Image Selection

```yaml
Primary: registry.redhat.io/rhel9/redis-7:latest
Fallback: quay.io/sclorg/redis-7-c9s:latest
```

## Health Probes

### LiteLLM Pods

**Readiness Probe:**
```yaml
httpGet:
  path: /health/readiness
  port: 4000
initialDelaySeconds: 10
periodSeconds: 10
```

**Liveness Probe:**
```yaml
httpGet:
  path: /health/liveness
  port: 4000
initialDelaySeconds: 30
periodSeconds: 15
```

### PostgreSQL

**Readiness/Liveness Probe:**
```yaml
exec:
  command:
    - /bin/sh
    - -c
    - pg_isready -U litemaas
```

### Redis

**Readiness Probe:**
```yaml
exec:
  command:
    - /bin/sh
    - -c
    - redis-cli ping | grep PONG
```

## Environment Variables

LiteLLM pods receive the following environment variables:

```yaml
# Database connection
DATABASE_URL: postgresql://litemaas:***@litemaas-postgres:5432/litemaas
DB_HOST: litemaas-postgres
DB_PORT: 5432
DB_NAME: litemaas
DB_USER: litemaas
DB_PASSWORD: *** (from secret)

# Redis cache
REDIS_HOST: litemaas-redis
REDIS_PORT: 6379

# LiteLLM configuration
LITELLM_MASTER_KEY: *** (from secret)
UI_USERNAME: admin
UI_PASSWORD: *** (from secret)
```

## Deployment Order

The HA workload deploys components in this order:

1. **Namespace creation**
2. **PostgreSQL 16**
   - Secret
   - Service
   - StatefulSet with PVC
   - Wait for ready
3. **Redis**
   - Service
   - Deployment
   - Wait for ready
4. **LiteLLM (HA)**
   - Secret
   - Deployment (multiple replicas)
   - Service
   - Route
   - Wait for all replicas ready

## Verification

### Check Pod Status

```bash
oc get pods -n litemaas
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
litemaas-5f7d8b9c4d-abc12   1/1     Running   0          5m
litemaas-5f7d8b9c4d-def34   1/1     Running   0          5m
litemaas-postgres-0         1/1     Running   0          10m
litemaas-redis-7b8c9d-xyz   1/1     Running   0          8m
```

### Check Services

```bash
oc get svc -n litemaas
```

Expected output:
```
NAME                TYPE        CLUSTER-IP       PORT(S)
litemaas            ClusterIP   172.30.x.x       4000/TCP
litemaas-postgres   ClusterIP   172.30.x.x       5432/TCP
litemaas-redis      ClusterIP   172.30.x.x       6379/TCP
```

### Check Route

```bash
oc get route -n litemaas
```

### Test Health Endpoint

```bash
ROUTE=$(oc get route litemaas -n litemaas -o jsonpath='{.spec.host}')
curl https://$ROUTE/health/livenessz
```

Expected: `{"status":"success"}`

## Troubleshooting

### Pods Not Starting

Check events:
```bash
oc get events -n litemaas --sort-by='.lastTimestamp'
```

Check pod logs:
```bash
oc logs -n litemaas deployment/litemaas -c litemaas
```

### Image Pull Errors

Verify image accessibility:
```bash
oc run test-image --image=registry.redhat.io/rhel9/postgresql-16:latest \
  --restart=Never -n litemaas -- echo "success"
```

### Database Connection Issues

Check PostgreSQL logs:
```bash
oc logs -n litemaas litemaas-postgres-0
```

Test connection from LiteLLM pod:
```bash
POD=$(oc get pod -n litemaas -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc exec -n litemaas $POD -- nc -zv litemaas-postgres 5432
```

### Redis Connection Issues

Test Redis connection:
```bash
POD=$(oc get pod -n litemaas -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc exec -n litemaas $POD -- nc -zv litemaas-redis 6379
```

## Removal

To remove the HA deployment:

```bash
oc delete namespace litemaas
```

Or use the standard removal playbook:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true \
  -e ocp4_workload_litemaas_ha_enabled=true
```

## Differences from Standard Deployment

| Feature | Standard | HA |
|---------|----------|-----|
| LiteLLM Replicas | 1 | 2+ (configurable) |
| Redis | No | Yes |
| PostgreSQL Version | 16 (docker.io) | 16 (Red Hat certified) |
| Image Registry | docker.io | registry.redhat.io (with fallback) |
| Health Probes | Basic | Enhanced |
| Resource Limits | Basic | Production-grade |
| Init Containers | PostgreSQL only | PostgreSQL + Redis |

## Integration with AgnosticV

To use HA mode in RHDP catalog:

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

# Set HA mode
ocp4_workload_litemaas_ha_enabled: true
ocp4_workload_litemaas_ha_litellm_replicas: 3
```

## Next Steps

- Monitor resource usage and adjust limits
- Configure Redis persistence if needed
- Set up PostgreSQL backups
- Implement horizontal pod autoscaling
- Add monitoring and alerting
