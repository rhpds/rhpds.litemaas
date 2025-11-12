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
- **Without OAuth**: Admin-only access per user
- **With OAuth**: Users login with OpenShift credentials + web UI
- Resources per user: 300m CPU, 768Mi RAM
- Total for 20 users: ~6 CPU cores, ~15Gi RAM

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
- Each user gets:
  - Admin URL: `https://litellm-admin-user1.<cluster>`
  - Frontend URL: `https://litellm-frontend-user1.<cluster>`
  - Login with OpenShift user credentials
  - Unique password: "RedHat2025!" (same for all users in lab)

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
- CPU: 300m request, 1000m limit
- Memory: 768Mi request, 1.5Gi limit
- Storage: 10Gi

**Scaling Examples:**
- **20 users**: 6 CPU cores, 15Gi RAM, 200Gi storage
- **40 users**: 12 CPU cores, 30Gi RAM, 400Gi storage
- **60 users**: 18 CPU cores, 46Gi RAM, 600Gi storage
- **80 users**: 24 CPU cores, 62Gi RAM, 800Gi storage

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

### OAuth Login Not Working

Check redirect URIs match:
```bash
oc get oauthclient litemaas-rhpds -o yaml
```

Should show both:
- `https://litellm-admin.<cluster>/api/auth/callback`
- `https://litellm-frontend.<cluster>/api/auth/callback`

### Backend Can't Connect to OAuth

Check backend logs:
```bash
oc logs deployment/litemaas-backend -n litemaas
```

Common issue: Self-signed certificates. Backend automatically sets `NODE_TLS_REJECT_UNAUTHORIZED=0`.

### Virtual Key Access Denied

Add model to "Personal Models" in LiteLLM Admin UI as a workaround.

---

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
