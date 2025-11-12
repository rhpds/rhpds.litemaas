# LiteMaaS - AI Model Serving Made Simple

Deploy an AI model gateway on OpenShift in 3 minutes. Give users controlled access to AI models through virtual API keys.

**Version:** 0.2.0

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

1. **Deploy models in OpenShift AI** (Granite, Llama, Mistral, etc.)
2. **Get model endpoint URL**
3. **Login to LiteLLM Admin UI**
4. **Click "Add Model":**
   - Provider: OpenAI-Compatible Endpoints
   - Model Name: `openai/granite-3-2-8b-instruct`
   - API Base: `https://your-model-endpoint/v1`
   - API Key: `<from OpenShift AI>`

5. **Create virtual keys for users:**
   - Go to Virtual Keys → Generate Key
   - Select models
   - Set budget (optional)
   - Copy key and share with users

**See [docs/ADDING_MODELS.md](docs/ADDING_MODELS.md) for detailed guide.**

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
