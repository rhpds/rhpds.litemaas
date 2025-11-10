# LiteMaaS Ansible Collection

Deploy LiteMaaS (Models as a Service) on OpenShift in 3 minutes.

**Version:** 0.2.0
**Upstream:** [rh-aiservices-bu/litemaas:0.1.2](https://github.com/rh-aiservices-bu/litemaas/releases/tag/0.1.2)

## What is LiteMaaS?

LiteMaaS provides an admin-managed AI model serving platform with:
- **LiteLLM Gateway**: Unified API for multiple AI model providers
- **Admin Interface**: Manage models, create user keys, track usage
- **OpenShift AI Integration**: Host local models (Granite, Llama, Mistral)
- **Virtual Key Management**: Control user access and budgets
- **Cost Tracking**: Monitor spending across all models

## Deployment Options

Choose the architecture that fits your needs:

### 1. Single Instance (Default)

**Use for:** Development, testing, single-user deployments

**Components:**
- 1 LiteLLM replica
- 1 PostgreSQL instance

**Deploy:**
```bash
ansible-playbook playbooks/deploy_litemaas.yml
```

---

### 2. Multi-User Lab Deployment

**Use for:** Training labs, workshops, isolated demo environments

**Architecture:**
```
litemaas-user1 → Dedicated PostgreSQL + LiteLLM
litemaas-user2 → Dedicated PostgreSQL + LiteLLM
litemaas-userN → Dedicated PostgreSQL + LiteLLM
```

**Deploy (10 users):**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=10
```

**Deploy (5 users with 2 LiteLLM replicas each):**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=5 \
  -e ocp4_workload_litemaas_litellm_replicas=2
```

**Benefits:**
- Each user gets isolated namespace and resources
- Dedicated PostgreSQL database per user
- Unique routes per user (litellm-user1-rhpds.apps...)
- No cross-contamination of data or usage
- Simple, lightweight architecture for labs
- Perfect for RHDP training workshops
- Scales from 1 to 50+ users

---

## Resource Requirements

Choose your deployment based on available cluster resources:

### Single Instance (Default)

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| PostgreSQL | 500m | 1000m | 512Mi | 1Gi | 10Gi |
| LiteLLM (1 replica) | 200m | 1000m | 512Mi | 1Gi | - |
| **Total** | **700m** | **2000m** | **~1Gi** | **~2Gi** | **10Gi** |

### Multi-User Lab (Per User - Optimized)

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| PostgreSQL | 200m | 500m | 256Mi | 512Mi | 10Gi |
| LiteLLM (1 replica) | 100m | 500m | 512Mi | 1Gi | - |
| **Per User Total** | **300m** | **1000m** | **~768Mi** | **~1.5Gi** | **10Gi** |

**Lab Sizing Examples:**

| Users | Total CPU Request | Total CPU Limit | Total Memory Request | Total Memory Limit | Total Storage |
|-------|-------------------|-----------------|----------------------|--------------------|---------------|
| **10 users** | 3000m (3 cores) | 10000m (10 cores) | ~7.7Gi | ~15Gi | 100Gi |
| **20 users** | 6000m (6 cores) | 20000m (20 cores) | ~15.4Gi | ~30Gi | 200Gi |
| **40 users** | 12000m (12 cores) | 40000m (40 cores) | ~30.8Gi | ~60Gi | 400Gi |
| **60 users** | 18000m (18 cores) | 60000m (60 cores) | ~46Gi | ~90Gi | 600Gi |
| **80 users** | 24000m (24 cores) | 80000m (80 cores) | ~62Gi | ~120Gi | 800Gi |

**Note:** Multi-user resources are optimized for lab environments. Actual usage will be lower than limits. For 60-80 user labs, ensure cluster has sufficient memory (90-120Gi limits).

---

## Prerequisites

- OpenShift 4.12+ cluster
- Cluster admin access
- `oc` CLI logged in
- Ansible 2.15+ with `kubernetes.core` collection
- **For 60-80 user labs:** Cluster with minimum 24+ cores, 40Gi+ RAM, 800Gi+ storage

## Deployment Instructions

Detailed step-by-step instructions for your platform:

Choose the deployment guide for your platform:

### Option 1: AWS Clusters

```bash
# 1. SSH to bastion
ssh lab-user@bastion.xxxxx.sandboxXXXX.opentlc.com

# 2. Clone the repository
cd ~
git clone https://github.com/prakhar1985/rhpds.litemaas.git
cd rhpds.litemaas

# 3. Build and install collection
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force

# 4. Deploy (auto-detects AWS storage)
ansible-playbook playbooks/deploy_litemaas.yml
```

**AWS uses `gp3-csi` storage class automatically.**

### Option 2: CNV/Virtualization Clusters

```bash
# 1. SSH to bastion
ssh lab-user@bastion.xxxxx.sandboxXXXX.opentlc.com

# 2. Create and activate k8s virtualenv (required for kubernetes library)
python3 -m venv /opt/virtualenvs/k8s
source /opt/virtualenvs/k8s/bin/activate

# 3. Install Python requirements
pip install kubernetes openshift

# 4. Clone the repository
cd ~
git clone https://github.com/prakhar1985/rhpds.litemaas.git
cd rhpds.litemaas

# 5. Install kubernetes.core collection
ansible-galaxy collection install kubernetes.core --force

# 6. Build and install LiteMaaS collection
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force

# 7. Deploy with ODF/Ceph storage (common in CNV)
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_postgres_storage_class=ocs-external-storagecluster-ceph-rbd
```

**CNV/Virtualization clusters typically use ODF (OpenShift Data Foundation) storage.**

#### Check Available Storage Classes

If deployment fails with PVC errors, check your storage classes:

```bash
# List storage classes
oc get storageclass

# Look for (default) marker or common CNV storage classes:
# - ocs-external-storagecluster-ceph-rbd
# - hostpath-provisioner
# - hostpath-csi

# Deploy with your storage class
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_postgres_storage_class=YOUR-STORAGE-CLASS
```

### Access Your Deployment

After deployment completes, you'll see the access information. You can retrieve it anytime:

#### Get Access Information

```bash
# Get all LiteMaaS access information
echo "========================================="
echo "LiteMaaS Access Information"
echo "========================================="
echo "LiteLLM Admin Portal: https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')"
echo "User API Endpoint: https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')"
echo ""
echo "Admin Credentials:"
echo "  Username: $(oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_USERNAME}' | base64 -d)"
echo "  Password: $(oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)"
echo "========================================="
```

**Quick Commands:**

```bash
# Just get the admin URL
echo "https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')"

# Just get the password
oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_PASSWORD}' | base64 -d

# Save to file
cat > ~/litemaas-access.txt <<EOF
LiteLLM Admin: https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')
Username: $(oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_USERNAME}' | base64 -d)
Password: $(oc get secret litellm-secret -n litemaas -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)
EOF
cat ~/litemaas-access.txt
```

## Adding AI Models

Once deployed, add AI models to make them available to users.

### Step 1: Get Model Details from OpenShift AI

From the OpenShift AI dashboard, get:
- **Endpoint URL** (e.g., `https://granite-3-2-8b-instruct-predictor-maas-apicast-production.apps.maas.redhatworkshops.io:443`)
- **API Key** from the OpenShift AI application

### Step 2: Find the Correct Model Name

**IMPORTANT**: Always check the `/v1/models` endpoint to get the exact model name:

```bash
curl https://YOUR-MODEL-ENDPOINT:443/v1/models \
  -H 'Authorization: Bearer YOUR-API-KEY'
```

**Example response:**
```json
{
  "object": "list",
  "data": [{
    "id": "granite-3-2-8b-instruct",  // ← This is the model name to use
    "object": "model",
    ...
  }]
}
```

### Step 3: Test the Endpoint

```bash
curl -X POST \
  https://YOUR-MODEL-ENDPOINT:443/v1/completions \
  -H 'Authorization: Bearer YOUR-API-KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "MODEL-NAME-FROM-STEP-2",
    "prompt": "Hello, what is AI?",
    "max_tokens": 50
  }'
```

### Step 4: Add Model in LiteLLM Admin UI

1. **Login to LiteLLM Admin Portal** (use credentials from deployment)

2. **Click "Add Model"**

3. **Fill in the form:**
   ```
   Provider: OpenAI-Compatible Endpoints (Together AI, etc.)
   LiteLLM Model Name(s): openai/MODEL-NAME-FROM-STEP-2
   Model Mappings:
     Public Name: MODEL-NAME-FROM-STEP-2
     LiteLLM Model: openai/MODEL-NAME-FROM-STEP-2
   Mode: Completion - /completions
   API Base: https://YOUR-MODEL-ENDPOINT/v1
   API Key: YOUR-API-KEY
   ```

   **Note**: Do not include the port (`:443`) in the API Base URL.

4. **Click "Add Model"**

5. **Add to Personal Models:**
   - Go to **Personal Models** section
   - Add: `openai/MODEL-NAME-FROM-STEP-2`

### Example: Common OpenShift AI Models

| Model | Endpoint Suffix | Correct Model Name |
|-------|----------------|-------------------|
| Granite 3.2 8B | `granite-3-2-8b-instruct-predictor-maas-apicast-production` | `granite-3-2-8b-instruct` |
| Mistral 7B | `mistral-7b-instruct-v0-3-maas-apicast-production` | `mistral-7b-instruct` |

### Create Virtual Keys for Users

1. **In LiteLLM Admin → Virtual Keys → Generate Key**
2. **Fill in:**
   ```
   User ID: user@example.com
   Models: openai/granite-3-2-8b-instruct, openai/mistral-7b-instruct
   Max Budget: 100 (optional)
   Duration: 30d (optional)
   ```
3. **Copy the generated key:** `sk-xxxxxx`
4. **Share with user:**
   ```
   API Endpoint: https://litellm-rhpds.apps.cluster-xxx.opentlc.com
   Virtual Key: sk-xxxxxx
   Available Models:
     - openai/granite-3-2-8b-instruct
     - openai/mistral-7b-instruct
   ```

### Troubleshooting: Virtual Key Model Access

**Issue**: Virtual key returns "key not allowed to access model" error

**Workaround**: Add the model to Personal Models section:

1. **In LiteLLM Admin UI → Personal Models**
2. **Add the same model** (e.g., `openai/granite-3-2-8b-instruct`)
3. **Virtual keys should now work**

This is a known workaround - proper fix TBD.

### Test User Access

```bash
# Get LiteLLM URL
LITELLM_URL=$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')

# Test with virtual key
curl https://${LITELLM_URL}/chat/completions \
  -H "Authorization: Bearer sk-YOUR-VIRTUAL-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/granite-3-2-8b-instruct",
    "messages": [{"role": "user", "content": "What is OpenShift?"}]
  }'
```

**For detailed model integration guides, see:**
- [Adding Models Guide](docs/ADDING_MODELS.md)
- [OpenShift AI Integration](docs/OPENSHIFT_AI_INTEGRATION.md)

## What Gets Deployed

All components deploy to the `litemaas` namespace:

| Component | Type | Description | Default |
|-----------|------|-------------|---------|
| **PostgreSQL** | StatefulSet | Persistent database for LiteLLM | ✅ Enabled |
| **LiteLLM Gateway** | Deployment | AI model proxy with admin UI | ✅ Enabled (1 replica) |
| **Routes** | Route | HTTPS access to admin portal | ✅ Enabled |
| **Secrets** | Secret | Admin credentials and API keys | ✅ Enabled |

**Note:** Frontend and Backend are optional and disabled by default. For admin-only deployments, only PostgreSQL and LiteLLM are deployed.

## Multi-User Lab Deployment Details

Additional details for multi-user deployments (see [Deployment Options](#deployment-options) for quick start commands).

### Use Cases

**1. Training Labs**
- 20 students, each gets isolated environment
- Deploy models once, share API keys per student
- No cross-contamination of data or usage

**2. Demo Environments**
- Multiple sales demos running concurrently
- Each demo has dedicated resources
- Clean environment per session

**3. Development Teams**
- Each team gets isolated LiteMaaS
- Independent model configurations
- Separate budgets and usage tracking

### Resource Requirements

Multi-user deployments use optimized resources for lab environments:

**Per user instance:**
- 1 namespace
- 1 PostgreSQL: 200m CPU request, 256Mi RAM request (512Mi limit)
- 1 LiteLLM: 100m CPU request, 256Mi RAM request (512Mi limit)
- Total per user: 300m CPU request, 512Mi RAM request, 10Gi storage

**Scalability (see [Resource Requirements](#resource-requirements) for detailed tables):**
- **10 users**: 3 CPU cores, 5Gi RAM, 100Gi storage
- **20 users**: 6 CPU cores, 10Gi RAM, 200Gi storage
- **40 users**: 12 CPU cores, 20Gi RAM, 400Gi storage
- **60 users**: 18 CPU cores, 30Gi RAM, 600Gi storage
- **80 users**: 24 CPU cores, 40Gi RAM, 800Gi storage

**Cluster Requirements for 60-80 User Labs:**
- Minimum: 24+ CPU cores, 40Gi+ RAM
- Recommended: 32+ CPU cores, 128Gi+ RAM
- Storage: 600-800Gi (thin provisioned)

**Note:** Multi-user mode is optimized for lab simplicity. Resources are intentionally lighter (256Mi RAM per component vs 512Mi+ in production).

### Showroom Integration

Multi-user deployments automatically provide per-user variables for Showroom catalog integration. Each user sees their own credentials when logged in.

**Example Showroom Content:**

```markdown
## Your LiteLLM Environment

Access your personal LiteLLM instance:

**Admin Portal:** [{{ litemaas_url }}]({{ litemaas_url }})

**Admin Credentials:**
- Username: `{{ litemaas_username }}`
- Password: `{{ litemaas_password }}`

**API Access:**
- Endpoint: `{{ litemaas_url }}`
- Master Key: `{{ litemaas_api_key }}`
- Namespace: `{{ litemaas_namespace }}`

### Quick Test

```bash
curl {{ litemaas_url }}/health/livenessz \
  -H "Authorization: Bearer {{ litemaas_api_key }}"
```
\```

**Available Variables:**

Each user automatically gets their own values for:
- `{{ litemaas_url }}` - LiteLLM Admin Portal URL
- `{{ litemaas_username }}` - Admin username (typically "admin")
- `{{ litemaas_password }}` - Admin password (unique per user)
- `{{ litemaas_api_key }}` - LiteLLM Master API key (unique per user)
- `{{ litemaas_namespace }}` - Kubernetes namespace (e.g., "litemaas-user1")

**Additionally**, numbered variables are available for cross-referencing:
- `{{ litemaas_user1_url }}`, `{{ litemaas_user2_url }}`, etc.
- `{{ litemaas_user1_password }}`, `{{ litemaas_user2_password }}`, etc.

### Removal

**Remove all user instances:**
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_multi_user=true \
  -e num_users=10 \
  -e ocp4_workload_litemaas_remove=true
```

This removes all namespaces: `litemaas-user1` through `litemaas-user10`.

## Variables

### Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_namespace` | `litemaas` | Deployment namespace |
| `ocp4_workload_litemaas_version` | `0.2.0` | LiteMaaS version |
| `ocp4_workload_litemaas_cloud_provider` | auto-detect | Cloud provider |

### PostgreSQL Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_postgres_storage_class` | auto-detect | Storage class |
| `ocp4_workload_litemaas_postgres_storage_size` | `10Gi` | PVC size |

### LiteLLM Scaling

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_litellm_replicas` | `1` | Number of LiteLLM instances |

### Redis Configuration (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_deploy_redis` | `false` | Enable Redis cache |
| `ocp4_workload_litemaas_redis_storage_size` | `5Gi` | Redis PVC size |
| `ocp4_workload_litemaas_redis_memory_limit` | `512Mi` | Redis memory limit |
| `ocp4_workload_litemaas_redis_cpu_limit` | `500m` | Redis CPU limit |

### Multi-User Lab Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_multi_user` | `false` | Enable multi-user lab deployment |
| `num_users` | `1` | Number of user instances to deploy |
| `ocp4_workload_litemaas_user_prefix` | `user` | Namespace prefix (user1, user2...) |
| `ocp4_workload_litemaas_multi_user_common_password` | `""` | Common admin password for all users (empty = auto-generate) |

**AgnosticV Example:**
```yaml
# In your AgnosticV catalog config
ocp4_workload_litemaas_multi_user: true
num_users: 60
ocp4_workload_litemaas_multi_user_common_password: "RedHat2025!"
```

**Showroom user.info Integration:**
```yaml
# All users get same password, individual URLs
user.info:
  litemaas_user1_url: "https://litellm-user1-rhpds.apps..."
  litemaas_user1_password: "RedHat2025!"
  litemaas_user2_url: "https://litellm-user2-rhpds.apps..."
  litemaas_user2_password: "RedHat2025!"
  # ... etc for all users
```

See `roles/ocp4_workload_litemaas/defaults/main.yml` for all variables.

## Examples

### Basic Deployment (Admin-Only)

```bash
ansible-playbook playbooks/deploy_litemaas.yml
```

This deploys:
- PostgreSQL database
- LiteLLM gateway with admin UI
- No frontend or backend (admin-only access)

### Enable Frontend/Backend (Optional)

If you want the web UI for end users:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_deploy_frontend=true \
  -e ocp4_workload_litemaas_deploy_backend=true \
  -e ocp4_workload_litemaas_oauth_enabled=true
```

### Custom Storage

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_postgres_storage_size=50Gi
```

### Remove Deployment

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true
```

## OpenShift AI Integration

Host local AI models using Red Hat OpenShift AI and make them available through LiteMaaS:

1. **Deploy models in OpenShift AI** (Granite, Llama, Mistral, etc.)
2. **Get inference endpoint URL**
3. **Add to LiteLLM** via Admin UI
4. **Create virtual keys** for users

See [docs/OPENSHIFT_AI_INTEGRATION.md](docs/OPENSHIFT_AI_INTEGRATION.md) for complete guide.

### Quick Example

```bash
# Get model endpoint from OpenShift AI
MODEL_URL=$(oc get inferenceservice granite-8b -n rhoai-models -o jsonpath='{.status.url}')

# Add to LiteLLM Admin UI:
#   Provider: OpenAI-Compatible
#   Model: granite-8b-instruct
#   API Base: ${MODEL_URL}/v1
```

## Prerequisites

- OpenShift 4.12+
- Ansible 2.15+
- `kubernetes.core` collection
- Cluster admin or project admin permissions

## Testing on RHDP Sandbox

```bash
# SSH to bastion
ssh lab-user@bastion.xxxxx.sandboxXXXX.opentlc.com

# Activate Python virtualenv
source /opt/virtualenvs/k8s/bin/activate

# Clone and deploy
git clone https://github.com/prakhar1985/rhpds.litemaas.git
cd rhpds.litemaas
ansible-playbook playbooks/deploy_litemaas.yml
```

## Changelog

### v0.2.0 (2025-11-10)

**Major Features: Horizontal Scaling, High Availability, and Multi-User Lab Deployment**

**New Features:**
- ✅ LiteLLM horizontal scaling (1-5 replicas)
- ✅ Redis Operator (Community, open source) for caching
- ✅ Production HA deployment architecture
- ✅ Multi-user lab deployment (isolated instances per user)
- ✅ Health probes for LiteLLM (liveness and readiness)
- ✅ Init containers to ensure proper startup order

**Architecture:**
- Single instance (default) - backward compatible
- Scaled + Redis - medium to large-scale production
- Multi-user - isolated instances for lab environments (1-80+ users)

**Configuration:**
- `ocp4_workload_litemaas_litellm_replicas` - Scale LiteLLM instances (1-5)
- `ocp4_workload_litemaas_deploy_redis` - Enable Redis cache (Community Operator)
- `ocp4_workload_litemaas_multi_user` - Enable multi-user lab mode
- `num_users` - Number of isolated user instances to deploy
- Multi-user resource optimization variables for 60-80 user labs

**Benefits:**
- Horizontal scaling for higher request volumes
- Redis caching reduces costs and latency
- High availability with load balancing
- Zero-downtime rolling updates
- Isolated environments for training labs and demos
- No licensing required (all open source)

**Multi-User Lab Features:**
- Each user gets dedicated namespace
- Isolated PostgreSQL + LiteLLM per user
- Unique routes per user (litellm-user1-rhpds.apps...)
- Simple, lightweight architecture (no Redis/PgBouncer overhead)
- Optimized resources: 300m CPU, 512Mi RAM per user
- User info data integration for Showroom catalog
- Perfect for RHDP training labs and workshops
- Scales from 1 to 80+ users (60-80 users tested)

**Documentation:**
- Added "Scaling and High Availability" section
- Added "Multi-User Lab Deployment" section
- Architecture comparison tables
- Deployment examples for all scenarios
- Resource requirement calculations
- Connection flow diagrams

**Resource Optimization:**
- Multi-user PostgreSQL: 200m CPU, 256Mi RAM (vs 500m, 512Mi)
- Multi-user LiteLLM: 100m CPU, 256Mi RAM (vs 200m, 512Mi)
- Enables 60-80 user labs on standard clusters (24+ cores, 40Gi+ RAM)
- Comprehensive resource requirement tables for all deployment modes

**User Info Integration:**
- Multi-user deployments send user.info data for each user
- Variables: URL, namespace, username, password, API key per user
- Ready for RHDP Showroom catalog integration
- Format: litemaas_user1_url, litemaas_user1_password, etc.

**Testing:**
- ✅ Backward compatible with v0.1.2
- ✅ Single instance deployment (default)
- ✅ Multi-replica with Redis
- ✅ Production HA with Redis + PgBouncer
- ✅ Multi-user deployment (1-10 users)
- ✅ Resource-optimized multi-user for 60-80 user labs

### v0.1.2 (2025-11-05)

**Compatibility:**
- Aligned with upstream [rh-aiservices-bu/litemaas:0.1.2](https://github.com/rh-aiservices-bu/litemaas/releases/tag/0.1.2)

**Features:**
- ✅ Admin-only architecture (no OAuth, frontend/backend disabled by default)
- ✅ LiteLLM virtual key management for user access control
- ✅ OpenShift AI model integration (Granite 3.2 8B, Mistral 7B)
- ✅ Platform-specific deployment guides (AWS, CNV/Virtualization)
- ✅ Automated PostgreSQL 16 + LiteLLM deployment
- ✅ Auto-detected storage classes (gp3-csi for AWS, ODF for CNV)

**Improvements:**
- Add init container to wait for PostgreSQL before LiteLLM starts
- Add health probes (`/health/liveness`, `/health/readiness`)
- Add `component: ai-proxy` label for better resource organization
- Update CPU request to 200m (matches upstream)
- Add model name discovery via `/v1/models` endpoint
- Add troubleshooting guide for virtual key access

**Documentation:**
- Platform-specific deployment instructions (AWS vs CNV)
- CNV virtualenv setup guide (create, activate, install requirements)
- Model addition workflow with endpoint testing
- Virtual key creation and testing examples
- Credential retrieval commands

**Testing:**
- ✅ Tested on AWS clusters (gp3-csi storage)
- ✅ Tested on CNV clusters (ODF/Ceph storage)
- ✅ Tested Granite 3.2 8B model integration
- ✅ Tested Mistral 7B model integration
- ✅ Tested virtual key creation and access control

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
