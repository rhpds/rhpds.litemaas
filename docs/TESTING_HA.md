# Testing LiteMaaS HA Deployment

Quick guide for testing the High Availability deployment.

## Prerequisites

1. **OpenShift Cluster Access**
   ```bash
   oc whoami
   ```

2. **Build and Install Collection**
   ```bash
   cd ~/work/code/rhpds.litemaas
   ansible-galaxy collection build --force
   ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force
   ```

## Test Deployment

### Default Test (2 replicas, litemaas-rhdp namespace)

```bash
ansible-playbook playbooks/test_ha_litemaas_rhdp.yml
```

### Custom Replicas

```bash
# 3 replicas
ansible-playbook playbooks/test_ha_litemaas_rhdp.yml \
  -e ocp4_workload_litemaas_ha_litellm_replicas=3

# 4 replicas
ansible-playbook playbooks/test_ha_litemaas_rhdp.yml \
  -e ocp4_workload_litemaas_ha_litellm_replicas=4
```

### Verbose Output

```bash
ansible-playbook playbooks/test_ha_litemaas_rhdp.yml -v
```

## Verification Steps

### 1. Check Namespace

```bash
oc get namespace litemaas-rhdp
```

Expected output:
```
NAME            STATUS   AGE
litemaas-rhdp   Active   2m
```

### 2. Check All Pods

```bash
oc get pods -n litemaas-rhdp
```

Expected output (2 replicas):
```
NAME                            READY   STATUS    RESTARTS   AGE
litemaas-7b8c9d4f5-abc12        1/1     Running   0          5m
litemaas-7b8c9d4f5-def34        1/1     Running   0          5m
litemaas-postgres-0             1/1     Running   0          8m
litemaas-redis-6f9d8c7-xyz89    1/1     Running   0          7m
```

### 3. Check Services

```bash
oc get svc -n litemaas-rhdp
```

Expected output:
```
NAME                TYPE        CLUSTER-IP       PORT(S)
litemaas            ClusterIP   172.30.x.x       4000/TCP
litemaas-postgres   ClusterIP   172.30.x.x       5432/TCP
litemaas-redis      ClusterIP   172.30.x.x       6379/TCP
```

### 4. Check Route

```bash
oc get route -n litemaas-rhdp
```

Get the route URL:
```bash
ROUTE_URL=$(oc get route litemaas -n litemaas-rhdp -o jsonpath='{.spec.host}')
echo "LiteMaaS URL: https://$ROUTE_URL"
```

### 5. Test Health Endpoint

```bash
ROUTE_URL=$(oc get route litemaas -n litemaas-rhdp -o jsonpath='{.spec.host}')
curl https://$ROUTE_URL/health/livenessz
```

Expected response:
```json
{"status":"success"}
```

### 6. Check Secrets

```bash
oc get secrets -n litemaas-rhdp | grep litemaas
```

Expected output:
```
litemaas-db       Opaque   4      10m
litellm-secret    Opaque   4      5m
```

### 7. Get Admin Credentials

```bash
# Username
oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.UI_USERNAME}' | base64 -d
echo

# Password
oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.UI_PASSWORD}' | base64 -d
echo

# API Key
oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d
echo
```

## Detailed Component Checks

### PostgreSQL

```bash
# Check PostgreSQL pod
oc get pod -n litemaas-rhdp -l app=litemaas-postgres

# Check PostgreSQL logs
oc logs -n litemaas-rhdp litemaas-postgres-0 --tail=50

# Test PostgreSQL connection from LiteLLM pod
POD=$(oc get pod -n litemaas-rhdp -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc exec -n litemaas-rhdp $POD -- nc -zv litemaas-postgres 5432

# Check PVC
oc get pvc -n litemaas-rhdp
```

### Redis

```bash
# Check Redis pod
oc get pod -n litemaas-rhdp -l app=litemaas-redis

# Check Redis logs
oc logs -n litemaas-rhdp -l app=litemaas-redis --tail=50

# Test Redis connection from LiteLLM pod
POD=$(oc get pod -n litemaas-rhdp -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc exec -n litemaas-rhdp $POD -- nc -zv litemaas-redis 6379

# Test Redis ping
oc exec -n litemaas-rhdp -l app=litemaas-redis -- redis-cli ping
```

### LiteLLM Pods

```bash
# Check all LiteLLM pods
oc get pod -n litemaas-rhdp -l app=litemaas

# Check logs for first pod
POD=$(oc get pod -n litemaas-rhdp -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc logs -n litemaas-rhdp $POD --tail=100

# Check environment variables
oc exec -n litemaas-rhdp $POD -- env | grep -E '(REDIS|DB_|DATABASE)'

# Describe pod to see init containers
oc describe pod -n litemaas-rhdp $POD
```

### Resource Usage

```bash
# Check resource requests and limits
oc describe deployment litemaas -n litemaas-rhdp | grep -A 5 "Limits\|Requests"

# Top pods
oc adm top pods -n litemaas-rhdp
```

## Testing Load Balancing

### Check Pod Distribution

```bash
# Make multiple requests and see which pod responds
for i in {1..10}; do
  oc logs -n litemaas-rhdp -l app=litemaas --tail=1 &
  curl -s https://$(oc get route litemaas -n litemaas-rhdp -o jsonpath='{.spec.host}')/health/livenessz > /dev/null
  sleep 1
done
```

### Scale Replicas

```bash
# Scale to 3 replicas
oc scale deployment litemaas -n litemaas-rhdp --replicas=3

# Verify
oc get pods -n litemaas-rhdp -l app=litemaas

# Scale back to 2
oc scale deployment litemaas -n litemaas-rhdp --replicas=2
```

## Troubleshooting

### Pods Not Starting

```bash
# Check events
oc get events -n litemaas-rhdp --sort-by='.lastTimestamp' | tail -20

# Describe problematic pod
oc describe pod <pod-name> -n litemaas-rhdp
```

### Image Pull Failures

```bash
# Check if Red Hat registry is accessible
oc run test-rhel9-postgres --image=registry.redhat.io/rhel9/postgresql-16:latest \
  --restart=Never -n litemaas-rhdp -- echo "success"

oc run test-rhel9-redis --image=registry.redhat.io/rhel9/redis-7:latest \
  --restart=Never -n litemaas-rhdp -- echo "success"

# Check pod status
oc get pod -n litemaas-rhdp test-rhel9-postgres
oc get pod -n litemaas-rhdp test-rhel9-redis

# Clean up
oc delete pod test-rhel9-postgres test-rhel9-redis -n litemaas-rhdp
```

### Init Container Issues

```bash
# Check init container logs
POD=$(oc get pod -n litemaas-rhdp -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc logs -n litemaas-rhdp $POD -c wait-for-postgres
oc logs -n litemaas-rhdp $POD -c wait-for-redis
```

### Database Connection Issues

```bash
# Check database URL in secret
oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.DATABASE_URL}' | base64 -d
echo

# Test connection manually
oc run test-db-conn --image=postgres:16 --restart=Never -n litemaas-rhdp -- \
  psql "postgresql://litemaas:$(oc get secret litemaas-db -n litemaas-rhdp -o jsonpath='{.data.password}' | base64 -d)@litemaas-postgres:5432/litemaas" -c "\l"

oc logs -n litemaas-rhdp test-db-conn
oc delete pod test-db-conn -n litemaas-rhdp
```

## Cleanup

### Remove Deployment

```bash
oc delete namespace litemaas-rhdp
```

Or use the removal playbook:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true \
  -e ocp4_workload_litemaas_namespace=litemaas-rhdp \
  -e ocp4_workload_litemaas_ha_enabled=true
```

## Performance Testing

### Basic Load Test

```bash
ROUTE_URL=$(oc get route litemaas -n litemaas-rhdp -o jsonpath='{.spec.host}')

# Simple load test (requires 'ab' - Apache Bench)
ab -n 100 -c 10 https://$ROUTE_URL/health/livenessz

# Or using curl in a loop
for i in {1..100}; do
  curl -s https://$ROUTE_URL/health/livenessz > /dev/null
  echo "Request $i complete"
done
```

### Monitor During Load

```bash
# Watch pods
watch 'oc get pods -n litemaas-rhdp'

# Watch resource usage
watch 'oc adm top pods -n litemaas-rhdp'
```

## Expected Test Results

| Component | Expected State | Check Command |
|-----------|----------------|---------------|
| Namespace | Active | `oc get namespace litemaas-rhdp` |
| PostgreSQL Pod | Running (1/1) | `oc get pod -n litemaas-rhdp -l app=litemaas-postgres` |
| Redis Pod | Running (1/1) | `oc get pod -n litemaas-rhdp -l app=litemaas-redis` |
| LiteLLM Pods | Running (2/2 or N/N) | `oc get pod -n litemaas-rhdp -l app=litemaas` |
| Services | 3 services (litemaas, postgres, redis) | `oc get svc -n litemaas-rhdp` |
| Route | 1 route (litemaas) | `oc get route -n litemaas-rhdp` |
| Secrets | 2 secrets (litemaas-db, litellm-secret) | `oc get secrets -n litemaas-rhdp \| grep litemaas` |
| PVC | 1 PVC (postgres-storage) | `oc get pvc -n litemaas-rhdp` |
| Health Check | {"status":"success"} | `curl https://<route>/health/livenessz` |

## Quick Reference

```bash
# Deploy
ansible-playbook playbooks/test_ha_litemaas_rhdp.yml

# Check status
oc get pods -n litemaas-rhdp

# Get URL
echo "https://$(oc get route litemaas -n litemaas-rhdp -o jsonpath='{.spec.host}')"

# Get credentials
echo "Username: $(oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.UI_USERNAME}' | base64 -d)"
echo "Password: $(oc get secret litellm-secret -n litemaas-rhdp -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)"

# Remove
oc delete namespace litemaas-rhdp
```
