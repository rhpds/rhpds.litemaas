# LiteMaaS - AI Model Serving Made Simple

Deploy an AI model gateway on OpenShift with High Availability. Give users controlled access to AI models through virtual API keys.

**Version:** 0.3.0

**CRITICAL MIGRATION NOTICE:** The old cluster `litellm-rhpds` is being shut down on **June 21, 2026**. All deployments must migrate to the new production cluster `maas-rhdp` before that date. See [Migration Guide](#cluster-migration-june-21-2026) below.

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
./deploy-litemaas.sh maas-rhdp

# HA with RHDP branding
./deploy-litemaas.sh maas-rhdp --rhdp

# Custom replicas
./deploy-litemaas.sh maas-rhdp --replicas 5

# With OAuth and custom routes
./deploy-litemaas.sh maas-rhdp --oauth --route-prefix litellm-prod

# Full RHDP production (OAuth + branding + custom routes)
./deploy-litemaas.sh maas-rhdp --oauth --rhdp --route-prefix litellm-prod

# Remove deployment
./deploy-litemaas.sh maas-rdhp --remove
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
| `ocp4_workload_litemaas_version` | `0.2.2` | Container image version |
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

## Cluster Migration (June 21, 2026)

**CRITICAL: Old cluster `litellm-rhpds` is being decommissioned June 21, 2026. Migrate to `maas-rdhp` before that date.**

### What's Changing

| Item | Old | New | Notes |
|------|-----|-----|-------|
| **Cluster** | `litellm-rhpds` | `maas-rdhp` | Production cluster migration |
| **API Endpoint** | `https://litellm-rhpds.apps.cluster.com` | `https://maas-rdhp.apps.cluster.com` | All API keys need migration |
| **Models** | Old catalog | New catalog | See [New Model Catalog](#new-model-catalog) |
| **Large Models (>120B)** | Self-service | Admin approval required | All >120B models now require approval |

### New Model Catalog

All models are available on `maas-rdhp`. Models are categorized by access level:

#### Vertex AI (via rh-summit-ai-workshops GCP)

Restricted models (>120B parameters require admin approval):

- `minimax-m2` — RESTRICTED (>120B, admin approval required)
- `qwen3-235b` — RESTRICTED (>120B, admin approval required)

Self-service models:

- `gpt-oss-120b` — Open access
- `gpt-oss-20b` — Open access

#### Locally Hosted (llm-hosting namespace)

All self-service unless noted:

- `granite-3-2-8b-instruct`
- `granite-4-0-h-tiny`
- `granite-2b-cpu`
- `llama-scout-17b`
- `llama-31-70b-cpu` — Self-service (70B is within tier)
- `Llama-Guard-3-1B`
- `codellama-7b-instruct`
- `deepseek-r1-distill-qwen-14b`
- `qwen3-14b`
- `qwen25-3b-cpu`
- `microsoft-phi-4`
- `phi3-mini-cpu`
- `nomic-embed-text-v1-5`
- `Docling`

### Migration Steps

1. **Update your API endpoints** from `https://litellm-rhpds.apps.cluster.com` to `https://maas-rdhp.apps.cluster.com`

2. **Generate new API keys** on the new cluster:
   ```bash
   # Old way (deprecated after June 21)
   curl https://litellm-rhpds.apps.cluster.com/key/generate ...
   
   # New way
   curl https://maas-rdhp.apps.cluster.com/key/generate ...
   ```

3. **Update your applications** to use new API endpoint and keys

4. **Request approval for large models** (if using models >120B):
   - Models like `minimax-m2` and `qwen3-235b` now require admin approval
   - Submit access request via LiteMaaS UI or contact admin

5. **Test your integration** on the new cluster before June 21

### FAQ

**Q: Will my old API keys still work after June 21?**
A: No. Old cluster `litellm-rhpds` will be decommissioned. You must migrate to `maas-rdhp` and generate new keys.

**Q: What about models >120B that I'm currently using?**
A: They are still available on `maas-rdhp`, but now require admin approval. Submit an access request immediately.

**Q: Do I need to change my code?**
A: Yes. Update your `api_base` URL and regenerate API keys on the new cluster.

**Q: What's the deadline?**
A: June 21, 2026. Plan your migration now.

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
