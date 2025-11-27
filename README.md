# LiteMaaS - AI Model Serving Made Simple

Deploy an AI model gateway on OpenShift in 3 minutes. Give users controlled access to AI models through virtual API keys.

**Version:** 0.3.0

## 📚 Documentation

- **[Infrastructure Team Guide](docs/INFRA_TEAM_GUIDE.md)** - Managing models after deployment
- **[Model Management Role](roles/ocp4_workload_litemaas_models/README.md)** - Dedicated role for model sync
- **[Examples](examples/)** - Configuration examples

---

## 🚀 Quick Deploy Script (Recommended)

**One command to deploy LiteMaaS - automatic Python venv setup included!**

The `deploy-litemaas.sh` script automatically:
- Creates and activates Python virtual environment
- Installs Ansible and Kubernetes Python dependencies
- Builds and installs the collection
- Deploys LiteMaaS with your chosen configuration

**Prerequisites:**
- OpenShift CLI (`oc`) installed and logged in
- Python 3 installed
- `jq` installed (for resource discovery)

**Single-User Deployment:**
```bash
./deploy-litemaas.sh litellm-rhpds
```

**Multi-User Lab (10 users):**
```bash
./deploy-litemaas.sh my-litemaas --multi-user --num-users 10
```

**High Availability (3 replicas):**
```bash
./deploy-litemaas.sh litellm-prod --ha --replicas 3
```

**Full Production Stack:**
```bash
./deploy-litemaas.sh litellm-rhpds \
  --ha --replicas 3 \
  --oauth \
  --backend \
  --frontend \
  --logos \
  --route-prefix litellm-prod
```

**Feature Flags:**
- `--oauth` - Enable OAuth authentication with OpenShift
- `--backend` - Deploy backend API service
- `--frontend` - Deploy frontend UI service
- `--logos` - Enable custom Red Hat logos and Beta labels
- `--route-prefix <name>` - Set custom route prefix (automatically sets all route names)

**Remove Deployment:**
```bash
./deploy-litemaas.sh litellm-rhpds --remove
```

**What the script does:**
1. ✅ Validates OpenShift login
2. ✅ Creates `.venv` directory (only first time)
3. ✅ Activates Python virtual environment
4. ✅ Installs/upgrades pip
5. ✅ Installs `ansible` and `kubernetes` Python packages
6. ✅ Builds Ansible collection from source
7. ✅ Installs collection to Ansible
8. ✅ Runs deployment playbook with your parameters
9. ✅ Shows access URLs and next steps

**After deployment, sync models:**
```bash
./sync-models.sh litellm-rhpds
```

---

## 📋 HA Deployment Examples

### Example 1: RHDP Production (Full Stack)
**Scenario:** Production deployment with OAuth, custom branding, and custom routes

```bash
./deploy-litemaas.sh litellm-rhpds \
  --ha \
  --replicas 3 \
  --oauth \
  --backend \
  --frontend \
  --logos \
  --route-prefix litellm-prod
```

**What you get:**
- Namespace: `litellm-rhpds`
- LiteLLM replicas: 3
- Routes:
  - API: `https://litellm-prod.apps.cluster.com`
  - Admin Backend: `https://litellm-prod-admin.apps.cluster.com`
  - Frontend: `https://litellm-prod-frontend.apps.cluster.com`
- Features: OAuth login, Red Hat logos, Beta labels

### Example 2: Development/Test Environment
**Scenario:** Simple HA setup for testing without OAuth

```bash
./deploy-litemaas.sh litellm-dev \
  --ha \
  --replicas 2
```

**What you get:**
- Namespace: `litellm-dev`
- LiteLLM replicas: 2
- Routes:
  - API: `https://litellm.apps.cluster.com`
- Features: Basic HA, no OAuth

### Example 3: Custom Namespace with Custom Routes
**Scenario:** Deploy to specific namespace with custom route naming

```bash
./deploy-litemaas.sh ai-models-production \
  --ha \
  --replicas 3 \
  --oauth \
  --backend \
  --frontend \
  --route-prefix ai-gateway
```

**What you get:**
- Namespace: `ai-models-production`
- LiteLLM replicas: 3
- Routes:
  - API: `https://ai-gateway.apps.cluster.com`
  - Admin Backend: `https://ai-gateway-admin.apps.cluster.com`
  - Frontend: `https://ai-gateway-frontend.apps.cluster.com`
- Features: OAuth, full stack

### Example 4: Staging Environment
**Scenario:** Staging with backend/frontend but no OAuth

```bash
./deploy-litemaas.sh litellm-staging \
  --ha \
  --replicas 2 \
  --backend \
  --frontend \
  --route-prefix litellm-stage
```

**What you get:**
- Namespace: `litellm-staging`
- LiteLLM replicas: 2
- Routes:
  - API: `https://litellm-stage.apps.cluster.com`
  - Admin Backend: `https://litellm-stage-admin.apps.cluster.com`
  - Frontend: `https://litellm-stage-frontend.apps.cluster.com`
- Features: Full stack without OAuth (API key only)

### Example 5: Multi-Cluster Setup
**Scenario:** Different deployments for different environments

```bash
# Cluster 1: Production
./deploy-litemaas.sh litellm-prod \
  --ha \
  --replicas 3 \
  --oauth \
  --backend \
  --frontend \
  --logos \
  --route-prefix litellm-prod

# Cluster 2: Staging
./deploy-litemaas.sh litellm-stage \
  --ha \
  --replicas 2 \
  --oauth \
  --backend \
  --frontend \
  --route-prefix litellm-stage

# Cluster 3: Development
./deploy-litemaas.sh litellm-dev \
  --ha \
  --replicas 1
```

### Example 6: Custom Domain Prefix
**Scenario:** Use organization-specific route prefix

```bash
./deploy-litemaas.sh redhat-ai-services \
  --ha \
  --replicas 3 \
  --oauth \
  --backend \
  --frontend \
  --logos \
  --route-prefix rh-ai
```

**What you get:**
- Namespace: `redhat-ai-services`
- Routes:
  - API: `https://rh-ai.apps.cluster.com`
  - Admin Backend: `https://rh-ai-admin.apps.cluster.com`
  - Frontend: `https://rh-ai-frontend.apps.cluster.com`

### Verify Your Deployment

After deployment, verify the routes:

```bash
# List all routes in namespace
oc get routes -n litellm-rhpds

# Get specific route URLs
oc get route litellm-prod -n litellm-rhpds -o jsonpath='{.spec.host}'

# Check pod status
oc get pods -n litellm-rhpds
```

### Sync Models

After successful deployment, sync models from LiteLLM to backend:

```bash
# Auto-discovery mode
./sync-models.sh litellm-rhpds

# Works with any custom namespace
./sync-models.sh ai-models-production
./sync-models.sh redhat-ai-services
```

### Quick Reference Table

| Scenario | Command |
|----------|---------|
| **Simple HA** | `./deploy-litemaas.sh <namespace> --ha --replicas 3` |
| **HA + OAuth** | `./deploy-litemaas.sh <namespace> --ha --replicas 3 --oauth --backend --frontend` |
| **Full Production** | `./deploy-litemaas.sh <namespace> --ha --replicas 3 --oauth --backend --frontend --logos --route-prefix <name>` |
| **Custom Routes** | `./deploy-litemaas.sh <namespace> --ha --replicas 2 --route-prefix my-custom-name` |
| **Single User** | `./deploy-litemaas.sh <namespace>` |
| **Multi-User Lab** | `./deploy-litemaas.sh <namespace> --multi-user --num-users 10` |
| **Remove** | `./deploy-litemaas.sh <namespace> --remove` |

### Route Naming Explained

When you use `--route-prefix <name>`, the script automatically sets:

| Route Type | Route Name (Resource) | Route Hostname |
|------------|----------------------|----------------|
| **API** | `<prefix>` | `https://<prefix>.apps.cluster.com` |
| **Admin Backend** | `<prefix>-admin` | `https://<prefix>-admin.apps.cluster.com` |
| **Frontend** | `<prefix>-frontend` | `https://<prefix>-frontend.apps.cluster.com` |

**Example:** `--route-prefix litellm-prod` creates:
- API: `https://litellm-prod.apps.cluster.com`
- Admin: `https://litellm-prod-admin.apps.cluster.com`
- Frontend: `https://litellm-prod-frontend.apps.cluster.com`

---

## 🎯 RHDP Production Deployment (Full Stack)

**Complete deployment with OAuth, custom logos, Beta labels, and custom routes:**

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_namespace=litellm-rhpds \
  -e ocp4_workload_litemaas_ha_litellm_replicas=3 \
  -e ocp4_workload_litemaas_oauth_enabled=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_enable_custom_logo=true \
  -e ocp4_workload_litemaas_api_route_name=litellm-prod \
  -e ocp4_workload_litemaas_admin_route_name=litellm-prod-admin \
  -e ocp4_workload_litemaas_frontend_route_name=litellm-prod-frontend \
  -e ocp4_workload_litemaas_api_route_prefix=litellm-prod \
  -e ocp4_workload_litemaas_admin_route_prefix=litellm-prod-admin \
  -e ocp4_workload_litemaas_frontend_route_prefix=litellm-prod-frontend
```

**What you get:**
- ✅ **High Availability**: 3 LiteLLM replicas with Redis caching
- ✅ **OAuth Integration**: Users login with OpenShift credentials
- ✅ **Custom Red Hat Logos**: RHDP branding on all pages
- ✅ **Beta Labels**: Login page, welcome message, and disclaimer
- ✅ **Custom Routes**:
  - API: `https://litellm-prod.apps.cluster.com`
  - Admin: `https://litellm-prod-admin.apps.cluster.com`
  - Frontend: `https://litellm-prod-frontend.apps.cluster.com`
- ✅ **Full Stack**: PostgreSQL + Redis + LiteLLM + Backend + Frontend
- ✅ **OAuth Persistence**: Secrets automatically reused on redeployment

**Post-Deployment: Sync Models**

```bash
# From bastion (automatic - reads from cluster)
cd ~/work/code/rhpds.litemaas
./sync-models.sh litellm-rhpds

# Or with explicit credentials
ansible-playbook playbooks/manage_models.yml \
  -e ocp4_workload_litemaas_models_namespace=litellm-rhpds \
  -e ocp4_workload_litemaas_models_litellm_url=https://litellm-prod.apps.cluster.com \
  -e ocp4_workload_litemaas_models_litellm_api_key=sk-xxxxx
```

**Key Variables Reference:**

| Variable | Purpose | Example |
|----------|---------|---------|
| `ocp4_workload_litemaas_namespace` | Namespace name | `litellm-rhpds` |
| `ocp4_workload_litemaas_ha_litellm_replicas` | Number of LiteLLM pods | `3` |
| `ocp4_workload_litemaas_oauth_enabled` | Enable OAuth login | `true` |
| `ocp4_workload_litemaas_deploy_backend` | Deploy backend API | `true` |
| `ocp4_workload_litemaas_deploy_frontend` | Deploy frontend UI | `true` |
| `ocp4_workload_litemaas_enable_custom_logo` | Use RHDP logos + Beta labels | `true` |
| `ocp4_workload_litemaas_api_route_name` | API route resource name | `litellm-prod` |
| `ocp4_workload_litemaas_api_route_prefix` | API hostname prefix | `litellm-prod` |
| `ocp4_workload_litemaas_admin_route_name` | Admin route resource name | `litellm-prod-admin` |
| `ocp4_workload_litemaas_admin_route_prefix` | Admin hostname prefix | `litellm-prod-admin` |
| `ocp4_workload_litemaas_frontend_route_name` | Frontend route resource name | `litellm-prod-frontend` |
| `ocp4_workload_litemaas_frontend_route_prefix` | Frontend hostname prefix | `litellm-prod-frontend` |

**Troubleshooting OAuth:**

If OAuth login fails after redeployment:
```bash
# Sync backend secret to match OAuth client
OAUTH_SECRET=$(oc get oauthclient litellm-rhpds -o jsonpath='{.secret}')
oc patch secret backend-secret -n litellm-rhpds -p "{\"data\":{\"OAUTH_CLIENT_SECRET\":\"$(echo -n $OAUTH_SECRET | base64)\"}}"
oc rollout restart deployment/litellm-backend -n litellm-rhpds
```

**Rebuilding Collection:**

```bash
cd ~/work/code/rhpds.litemaas
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force
```

---

## Quick Start - Pick Your Scenario

Choose the deployment that matches your needs:

### 1. 🧪 **POC/Testing** - Single Instance (No OAuth)
Perfect for: Quick tests, demos, POCs

```bash
ansible-playbook playbooks/deploy_litemaas.yml
```

**What you get:**
- Simple admin-only setup
- Access LiteLLM admin UI at `https://litellm-admin.<cluster>`
- Create virtual keys for users
- Minimal resources: 700m CPU, 1Gi RAM

---

### 2. 👥 **Training Labs** - Multi-User (20-80 users)

Perfect for: Workshops, training sessions, each user needs isolated environment

**Without OAuth (simpler):**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=20 \
  -e ocp4_workload_litemaas_multi_user_common_password="RedHat2025!"
```

**With OAuth + Frontend + Backend:**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=20 \
  -e ocp4_workload_litemaas_oauth_enabled=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_multi_user_common_password="RedHat2025!"
```

**What you get:**
- Each user: `litemaas-user1`, `litemaas-user2`, etc.
- **Without OAuth**:
  - Admin-only access per user via LiteLLM Admin UI
  - Admin URL: `https://litellm-admin-user1.<cluster>`
  - Components: PostgreSQL + LiteLLM
  - Resources per user: 300m CPU, 768Mi RAM
- **With OAuth**:
  - Users login with OpenShift credentials
  - Admin URL: `https://litellm-admin-user1.<cluster>`
  - Frontend URL: `https://litellm-frontend-user1.<cluster>`
  - Components: PostgreSQL + LiteLLM + Backend + Frontend
  - Resources per user: 450m CPU, 1152Mi RAM
- Total for 20 users (with OAuth): ~9 CPU cores, ~23Gi RAM

---

### 3. 🚀 **Production** - High Availability with OAuth

Perfect for: Production workloads, high traffic, need redundancy

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_oauth_enabled=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_ha_litellm_replicas=3
```

**What you get:**
- 3 LiteLLM replicas (auto load-balanced)
- Redis caching (reduces costs + latency)
- PostgreSQL database
- OAuth login via OpenShift
- Admin UI: `https://litellm-admin.<cluster>`
- User UI: `https://litellm-frontend.<cluster>`
- Resources: ~3 CPU cores, ~4Gi RAM

---

## What Are These Components?

### **LiteLLM (Always Deployed)**
- The AI model gateway
- Provides unified API for multiple AI providers (OpenAI, Azure, local models)
- Includes admin web UI for managing models and creating user keys

### **Backend API (Optional)**
- REST API layer between frontend and LiteLLM
- Handles OAuth authentication
- User management and session handling
- **When to use**: When deploying with OAuth and frontend

### **Frontend Web UI (Optional)**
- User-facing web interface
- Login with OpenShift credentials
- Browse available models
- Make API calls through web interface
- **When to use**: When you want users to have a web UI instead of just API access

### **Without Frontend/Backend:**
- Admin logs into LiteLLM admin UI
- Admin creates virtual API keys for users
- Users use API keys to call models directly via API
- Simpler, no OAuth needed

### **With Frontend/Backend:**
- Users login via OpenShift (OAuth)
- Users get web interface to interact with models
- Still supports API access
- More complex, requires OAuth setup

---

## AgnosticV Example - Multi-User Lab

For RHDP catalog deployments with 60 users:

```yaml
# catalog_item.yml
ocp4_workload_litemaas_multi_user: true
num_users: 60
ocp4_workload_litemaas_oauth_enabled: true
ocp4_workload_litemaas_deploy_backend: true
ocp4_workload_litemaas_deploy_frontend: true
ocp4_workload_litemaas_multi_user_common_password: "RedHat2025!"
ocp4_workload_litemaas_postgres_storage_class: "ocs-external-storagecluster-ceph-rbd"  # CNV clusters
```

**What happens:**
- 60 namespaces created: `litemaas-user1` through `litemaas-user60`
- Single OAuthClient with 120 redirect URIs (2 per user: admin + frontend)
- Each user gets isolated environment:
  - PostgreSQL database (10Gi)
  - LiteLLM gateway (1 replica)
  - Backend API (with database migrations)
  - Frontend web UI
  - Admin URL: `https://litellm-admin-user1.<cluster>`
  - Frontend URL: `https://litellm-frontend-user1.<cluster>`
  - Login with OpenShift credentials (username: `user1`, password: "RedHat2025!")

**Resource requirements (60 users):**
- CPU: ~27 cores (450m per user)
- Memory: ~70Gi (1152Mi per user)
- Storage: ~600Gi (10Gi per user)

**User Info Variables (for Showroom):**
```yaml
user.info:
  litemaas_user1_admin_url: "https://litellm-admin-user1.apps..."
  litemaas_user1_frontend_url: "https://litellm-frontend-user1.apps..."
  litemaas_user1_password: "RedHat2025!"
  litemaas_user1_username: "admin"
  # ... user2, user3, etc.
```

---

## All Configuration Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_namespace` | `litemaas` | Deployment namespace |
| `ocp4_workload_litemaas_version` | `0.2.0` | Version to deploy |

### Multi-User Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_multi_user` | `false` | Enable multi-user mode |
| `num_users` | `1` | Number of user instances |
| `ocp4_workload_litemaas_user_prefix` | `user` | Namespace prefix (user1, user2...) |
| `ocp4_workload_litemaas_multi_user_common_password` | `""` | Shared password for all users (empty = random per user) |

### OAuth Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_oauth_enabled` | `false` | Enable OAuth login |
| `ocp4_workload_litemaas_oauth_provider` | `openshift` | OAuth provider (openshift or google) |
| `ocp4_workload_litemaas_oauth_client_id` | `litemaas-rhpds` | OAuth client ID |

### Component Control

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_deploy_backend` | `true` | Deploy backend API (needed for OAuth) |
| `ocp4_workload_litemaas_deploy_frontend` | `true` | Deploy frontend web UI (needed for OAuth) |

### High Availability

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_ha_enabled` | `false` | Enable HA mode |
| `ocp4_workload_litemaas_ha_litellm_replicas` | `2` | Number of LiteLLM replicas |
| `ocp4_workload_litemaas_ha_enable_redis` | `true` | Enable Redis cache (HA mode) |
| `ocp4_workload_litemaas_ha_enable_postgres` | `true` | Enable PostgreSQL (HA mode) |

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_postgres_storage_class` | auto-detect | Storage class (gp3-csi for AWS, ODF for CNV) |
| `ocp4_workload_litemaas_postgres_storage_size` | `10Gi` | PostgreSQL PVC size |

**See `roles/ocp4_workload_litemaas/defaults/main.yml` for all variables.**

---

## Resource Requirements

### Single Instance
- CPU: 700m request, 2000m limit
- Memory: 1Gi request, 2Gi limit
- Storage: 10Gi

### High Availability (3 replicas + Redis)
- CPU: ~3 cores request, ~5 cores limit
- Memory: ~4Gi request, ~6Gi limit
- Storage: 15Gi (10Gi PostgreSQL + 5Gi Redis)

### Multi-User (per user)

**Without OAuth (PostgreSQL + LiteLLM only):**
- CPU: 300m request, 1000m limit
- Memory: 768Mi request, 1.5Gi limit
- Storage: 10Gi

**With OAuth (PostgreSQL + LiteLLM + Backend + Frontend):**
- CPU: 450m request, 1450m limit
- Memory: 1152Mi request, 2.2Gi limit
- Storage: 10Gi

**Scaling Examples (with OAuth):**
- **20 users**: 9 CPU cores, 23Gi RAM, 200Gi storage
- **40 users**: 18 CPU cores, 46Gi RAM, 400Gi storage
- **60 users**: 27 CPU cores, 70Gi RAM, 600Gi storage
- **80 users**: 36 CPU cores, 92Gi RAM, 800Gi storage

---

## Installation

**AWS Cluster:**
```bash
git clone https://github.com/rhpds/rhpds.litemaas.git
cd rhpds.litemaas
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force
```

**CNV Cluster (OpenShift Virtualization):**
```bash
# Setup Python environment
python3 -m venv /opt/virtualenvs/k8s
source /opt/virtualenvs/k8s/bin/activate
pip install kubernetes openshift

# Install collection
ansible-galaxy collection install kubernetes.core --force
git clone https://github.com/rhpds/rhpds.litemaas.git
cd rhpds.litemaas
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force
```

### Storage Class Configuration

**AWS Clusters:**
- Auto-detected: `gp3-csi` (default)
- No additional configuration needed

**CNV Clusters (OpenShift Virtualization):**
- Use ODF storage: `ocs-external-storagecluster-ceph-rbd`
- Add to all deployments:
  ```bash
  -e ocp4_workload_litemaas_postgres_storage_class="ocs-external-storagecluster-ceph-rbd"
  ```

**Examples:**

```bash
# POC on CNV
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_postgres_storage_class="ocs-external-storagecluster-ceph-rbd"

# Multi-User on CNV
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=20 \
  -e ocp4_workload_litemaas_oauth_enabled=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_multi_user_common_password="RedHat2025!" \
  -e ocp4_workload_litemaas_postgres_storage_class="ocs-external-storagecluster-ceph-rbd"

# HA on CNV
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_oauth_enabled=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_ha_litellm_replicas=3 \
  -e ocp4_workload_litemaas_postgres_storage_class="ocs-external-storagecluster-ceph-rbd"
```

---

## Access Your Deployment

### Get Admin Credentials

**Single/HA Instance:**
```bash
# Get admin URL
echo "Admin UI: https://$(oc get route litemaas -n litemaas -o jsonpath='{.spec.host}')"

# Get admin password
oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_PASSWORD}' | base64 -d
```

**With Frontend (OAuth enabled):**
```bash
# Get frontend URL
echo "Frontend: https://$(oc get route litemaas-frontend -n litemaas -o jsonpath='{.spec.host}')"

# Login with OpenShift credentials
```

**Multi-User:**
```bash
# List all user instances
oc get routes -A | grep litellm-admin

# Get specific user's admin password
oc get secret litellm-secret -n litemaas-user1 -o jsonpath='{.data.UI_PASSWORD}' | base64 -d
```

---

## Adding AI Models

### Option 1: Automated Model Configuration (Recommended)

Pre-configure models during deployment using Ansible variables:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e '{
    "ocp4_workload_litemaas_litellm_models": [
      {
        "model_name": "granite-3-8b",
        "litellm_model": "openai/granite-3-2-8b-instruct",
        "api_base": "https://granite-model.apps.cluster.com/v1",
        "api_key": "sk-xxxxx",
        "rpm": 120,
        "tpm": 100000
      },
      {
        "model_name": "llama-3-8b",
        "litellm_model": "openai/llama-3-8b-instruct",
        "api_base": "https://llama-model.apps.cluster.com/v1",
        "api_key": "sk-yyyyy"
      }
    ]
  }'
```

**AgnosticV Example:**
```yaml
# catalog_item.yml
ocp4_workload_litemaas_litellm_models:
  - model_name: "granite-3-8b"
    litellm_model: "openai/granite-3-2-8b-instruct"
    api_base: "https://granite-model.apps.cluster.com/v1"
    api_key: "sk-xxxxx"
    rpm: 120
    tpm: 100000
```

**Model Parameters:**
- `model_name`: Display name for users
- `litellm_model`: LiteLLM model identifier (format: `provider/model-name`)
- `api_base`: Model endpoint URL (OpenAI-compatible)
- `api_key`: Authentication key for the model endpoint
- `rpm` (optional): Requests per minute limit
- `tpm` (optional): Tokens per minute limit

### Option 2: Adding Models via LiteLLM Admin UI + Sync

**For infrastructure teams:**

1. **Login to LiteLLM Admin UI** at `https://litellm-admin.<cluster>`
2. **Click "Add Model":**
   - Provider: OpenAI-Compatible Endpoints
   - Model Name: `openai/granite-3-2-8b-instruct`
   - API Base: `https://your-model-endpoint/v1`
   - API Key: `<from OpenShift AI>`
3. **Sync model to backend database** (required for users to create subscriptions):

**Quick method (automatic):**
```bash
./sync-models.sh litemaas
```

**Manual method:**
```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.<cluster> \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_list=[] \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true
```

**Why sync is needed:**
- Models added via UI are only in LiteLLM
- Users need models in the backend database to create subscriptions
- The sync process copies all LiteLLM models to backend database

**See [docs/INFRA_TEAM_GUIDE.md](docs/INFRA_TEAM_GUIDE.md) for detailed instructions.**

### Option 3: Managing Models Post-Deployment

Use the dedicated model management playbook:

```bash
# Copy example configuration
cp examples/models.yml my-models.yml

# Edit with your models
vi my-models.yml

# Add/sync models
ansible-playbook playbooks/manage_models.yml -e @my-models.yml
```

**See [roles/ocp4_workload_litemaas_models/README.md](roles/ocp4_workload_litemaas_models/README.md) for detailed guide.**

---

## Remove Deployment

**Single/HA Instance:**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true
```

**Multi-User:**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=20 \
  -e ocp4_workload_litemaas_remove=true
```

---

## Prerequisites

- OpenShift 4.12+
- Ansible 2.15+
- `kubernetes.core` collection
- Cluster admin or project admin permissions

---

## Testing on RHDP Sandbox

```bash
# SSH to bastion
ssh lab-user@bastion.xxxxx.sandboxXXXX.opentlc.com

# Activate Python virtualenv
source /opt/virtualenvs/k8s/bin/activate

# Clone and deploy
git clone https://github.com/rhpds/rhpds.litemaas.git
cd rhpds.litemaas
ansible-playbook playbooks/deploy_litemaas.yml
```

---

## Troubleshooting

### OAuth Login Not Working (Single/HA)

Check redirect URIs match:
```bash
oc get oauthclient litemaas-rhpds -o yaml
```

Should show both:
- `https://litellm-admin.<cluster>/api/auth/callback`
- `https://litellm-frontend.<cluster>/api/auth/callback`

### OAuth Login Not Working (Multi-User)

Check all user redirect URIs are registered:
```bash
# Should show 2 URIs per user (admin + frontend)
oc get oauthclient litemaas-rhpds -o jsonpath='{.redirectURIs}' | jq
```

For 20 users, should see 40 redirect URIs total.

### Backend Can't Connect to OAuth

Check backend logs:
```bash
oc logs deployment/litemaas-backend -n litemaas
```

Common issue: Self-signed certificates. Backend automatically sets `NODE_TLS_REJECT_UNAUTHORIZED=0`.

### Database Migrations Failed

Check migration logs:
```bash
oc logs deployment/litemaas-backend -n litemaas -c run-migrations
```

If you see npm permission errors, the init container now uses `/tmp` for npm cache (fixed in v0.2.0+).

### Backend Pod Stuck in Init

Check database connectivity:
```bash
# Check if PostgreSQL is ready
oc get pods -n litemaas -l app=litemaas-postgres

# Check database service
oc get svc -n litemaas postgres

# View init container logs
oc logs deployment/litemaas-backend -n litemaas -c wait-for-database
```

### Multi-User: Check Specific User

```bash
# Replace user1 with your user number
USER=user1

# Check all pods for user
oc get pods -n litemaas-$USER

# Check backend logs
oc logs -n litemaas-$USER deployment/litemaas-backend --tail=50

# Check migration logs
oc logs -n litemaas-$USER deployment/litemaas-backend -c run-migrations

# Verify database tables
oc exec -n litemaas-$USER postgres-0 -- psql -U litemaas -d litemaas -c '\dt'

# Get user credentials
echo "Admin URL: https://litellm-admin-$USER.<cluster>"
echo "Frontend URL: https://litellm-frontend-$USER.<cluster>"
echo "Password: $(oc get secret litellm-secret -n litemaas-$USER -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)"
```

### Virtual Key Access Denied

Add model to "Personal Models" in LiteLLM Admin UI as a workaround.

---

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
