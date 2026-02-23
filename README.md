# LiteMaaS - AI Model Serving Made Simple

Deploy an AI model gateway on OpenShift with High Availability. Give users controlled access to AI models through virtual API keys.

**Version:** 0.3.0

## Documentation

- **[Infrastructure Team Guide](docs/INFRA_TEAM_GUIDE.md)** - Managing models after deployment
- **[Model Management Role](roles/ocp4_workload_litemaas_models/README.md)** - Dedicated role for model sync
- **[RHDP Branding](docs/RHDP_BRANDING.md)** - Red Hat Demo Platform branding
- **[HA Deployment Details](docs/HA_DEPLOYMENT.md)** - Architecture and configuration reference
- **[Backup and Disaster Recovery](docs/BACKUP.md)** - Automated backups to S3 and restore procedures
- **[OAuth Login](docs/OAUTH_LOGIN.md)** - OpenShift OAuth integration

---

## Two Deployment Options

### Option 1: Standard HA Deployment

```bash
./deploy-litemaas.sh litellm-rhpds
```

Or with Ansible directly:

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml
```

**What you get:**
- 3 LiteLLM replicas (load-balanced)
- Redis caching
- PostgreSQL 16 database
- OAuth login via OpenShift (enabled by default)
- Backend API + Frontend UI
- Admin UI: `https://litellm.<cluster>`
- User UI: `https://litellm-frontend.<cluster>`

### Option 2: HA with RHDP Branding

```bash
./deploy-litemaas.sh litellm-rhpds --rhdp
```

Or with Ansible directly:

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_branding_enabled=true
```

**Same as Option 1, plus:**
- Red Hat Demo Platform logos (light and dark theme)
- Service attribution footer
- Custom favicon

---

## Quick Deploy Script (Recommended)

The `deploy-litemaas.sh` script automatically:
- Creates and activates Python virtual environment
- Installs Ansible and Kubernetes Python dependencies
- Builds and installs the collection
- Deploys LiteMaaS with your chosen configuration

**Prerequisites:**
- OpenShift CLI (`oc`) installed and logged in
- Python 3 installed
- `jq` installed (for resource discovery)

### Examples

```bash
# Standard HA deployment
./deploy-litemaas.sh litellm-rhpds

# HA with RHDP branding
./deploy-litemaas.sh litellm-rhpds --rhdp

# Custom replicas
./deploy-litemaas.sh litellm-rhpds --replicas 5

# With OAuth and custom routes
./deploy-litemaas.sh litellm-rhpds --oauth --route-prefix litellm-prod

# Full RHDP production (OAuth + branding + custom routes)
./deploy-litemaas.sh litellm-rhpds --oauth --rhdp --route-prefix litellm-prod

# Remove deployment
./deploy-litemaas.sh litellm-rhpds --remove
```

### Script Options

| Option | Description |
|--------|-------------|
| `--replicas <count>` | Number of LiteLLM replicas (default: 3) |
| `--oauth` | Enable OAuth authentication with OpenShift |
| `--rhdp` | Enable RHDP branding (logos + footer) |
| `--route-prefix <name>` | Set custom route prefix |
| `--remove` | Remove existing deployment |
| `-e <key=value>` | Pass extra variables to Ansible |

### Route Naming

When you use `--route-prefix <name>`, the script automatically sets:

| Route Type | Hostname |
|------------|----------|
| API | `https://<prefix>.apps.cluster.com` |
| Admin Backend | `https://<prefix>-admin.apps.cluster.com` |
| Frontend | `https://<prefix>-frontend.apps.cluster.com` |

---

## Ansible Playbook Usage

### Deploy

```bash
# Standard HA (OAuth enabled by default)
ansible-playbook playbooks/deploy_litemaas_ha.yml

# With RHDP branding
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_branding_enabled=true

# Custom namespace and replicas
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_namespace=litellm-production \
  -e ocp4_workload_litemaas_ha_litellm_replicas=5

# Disable OAuth for testing
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_oauth_enabled=false
```

### Remove

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_remove=true
```

---

## Key Configuration Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_namespace` | `litemaas` | Deployment namespace |
| `ocp4_workload_litemaas_version` | `latest` | Container image version |
| `ocp4_workload_litemaas_ha_litellm_replicas` | `3` | Number of LiteLLM replicas |

### OAuth Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_oauth_enabled` | `true` (in playbook) | Enable OAuth login |
| `ocp4_workload_litemaas_oauth_provider` | `openshift` | OAuth provider |

### Component Control

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_deploy_backend` | `true` | Deploy backend API |
| `ocp4_workload_litemaas_deploy_frontend` | `true` | Deploy frontend UI |
| `ocp4_workload_litemaas_branding_enabled` | `false` | Enable RHDP branding |

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_postgres_storage_class` | auto-detect | Storage class |
| `ocp4_workload_litemaas_postgres_storage_size` | `10Gi` | PostgreSQL PVC size |

**See `roles/ocp4_workload_litemaas/defaults/main.yml` and `roles/ocp4_workload_litemaas/defaults/ha.yml` for all variables.**

---

## What Are These Components?

### LiteLLM (Always Deployed)
- AI model gateway providing unified API for multiple AI providers
- Includes admin web UI for managing models and creating user keys

### Backend API (Always Deployed in HA)
- REST API layer handling OAuth authentication
- User management and session handling

### Frontend Web UI (Always Deployed in HA)
- User-facing web interface for browsing models and making API calls
- Login with OpenShift credentials

### PostgreSQL 16
- Persistent database for LiteLLM configuration and user data

### Redis
- Caching layer for improved performance and reduced latency

---

## Adding AI Models

### Option 1: Automated Model Configuration

Pre-configure models during deployment:

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e '{
    "ocp4_workload_litemaas_litellm_models": [
      {
        "model_name": "granite-3-8b",
        "litellm_model": "openai/granite-3-2-8b-instruct",
        "api_base": "https://granite-model.apps.cluster.com/v1",
        "api_key": "sk-xxxxx",
        "rpm": 120,
        "tpm": 100000
      }
    ]
  }'
```

### Option 2: Sync Models from LiteLLM Admin UI

```bash
# Add models via LiteLLM admin UI, then sync to backend
./sync-models.sh litellm-rhpds
```

See [docs/INFRA_TEAM_GUIDE.md](docs/INFRA_TEAM_GUIDE.md) for detailed instructions.

---

## Resource Requirements (3 replicas + Redis)

- CPU: ~3 cores request, ~5 cores limit
- Memory: ~4Gi request, ~6Gi limit
- Storage: 10Gi (PostgreSQL)

---

## Installation

```bash
git clone https://github.com/rhpds/rhpds.litemaas.git
cd rhpds.litemaas
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force
```

Or use `./deploy-litemaas.sh` which handles everything automatically.

---

## Access Your Deployment

```bash
# Get admin URL
echo "Admin UI: https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')"

# Get frontend URL
echo "Frontend: https://$(oc get route litellm-frontend -n litemaas -o jsonpath='{.spec.host}')"

# Login with OpenShift credentials (if OAuth enabled)
```

---

## AgnosticV Integration

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

# HA configuration
ocp4_workload_litemaas_ha_litellm_replicas: 3
ocp4_workload_litemaas_oauth_enabled: true
ocp4_workload_litemaas_deploy_backend: true
ocp4_workload_litemaas_deploy_frontend: true

# Optional: RHDP branding
ocp4_workload_litemaas_branding_enabled: true
```

---

## Troubleshooting

### OAuth Login Not Working

Check redirect URIs match:
```bash
oc get oauthclient litemaas -o yaml
```

Should show both:
- `https://litellm.<cluster>/api/auth/callback`
- `https://litellm-frontend.<cluster>/api/auth/callback`

### Backend Can't Connect to OAuth

```bash
oc logs deployment/litellm-backend -n litemaas
```

### Database Issues

```bash
# Check PostgreSQL logs
oc logs -n litemaas -l app=litellm-postgres

# Check migration logs
oc logs deployment/litellm-backend -n litemaas -c run-migrations
```

### Pod Status

```bash
oc get pods -n litemaas
oc get events -n litemaas --sort-by='.lastTimestamp'
```

---

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
