# LiteMaaS Ansible Collection

Deploy LiteMaaS (Models as a Service) on OpenShift in 3 minutes.

**Version:** 0.1.2
**Upstream:** [rh-aiservices-bu/litemaas:0.1.2](https://github.com/rh-aiservices-bu/litemaas/releases/tag/0.1.2)

## What is LiteMaaS?

LiteMaaS provides an admin-managed AI model serving platform with:
- **LiteLLM Gateway**: Unified API for multiple AI model providers
- **Admin Interface**: Manage models, create user keys, track usage
- **OpenShift AI Integration**: Host local models (Granite, Llama, Mistral)
- **Virtual Key Management**: Control user access and budgets
- **Cost Tracking**: Monitor spending across all models

## Quick Start

### Prerequisites

- OpenShift 4.12+ cluster
- Cluster admin access
- `oc` CLI logged in
- Ansible 2.15+ with `kubernetes.core` collection

## Deployment Instructions

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
   API Base: https://YOUR-MODEL-ENDPOINT:443/v1
   API Key: YOUR-API-KEY
   ```

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
   API Endpoint: https://litellm-admin.apps.cluster-xxx.opentlc.com
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

| Component | Type | Description |
|-----------|------|-------------|
| **PostgreSQL** | StatefulSet | Persistent database for LiteLLM |
| **LiteLLM Gateway** | Deployment | AI model proxy with admin UI |
| **Routes** | Route | HTTPS access to admin portal |
| **Secrets** | Secret | Admin credentials and API keys |

**Note:** Frontend and Backend are optional and disabled by default. For admin-only deployments, only PostgreSQL and LiteLLM are deployed.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_namespace` | `litemaas` | Deployment namespace |
| `ocp4_workload_litemaas_version` | `0.1.2` | LiteMaaS version |
| `ocp4_workload_litemaas_cloud_provider` | auto-detect | Cloud provider |
| `ocp4_workload_litemaas_postgres_storage_class` | auto-detect | Storage class |
| `ocp4_workload_litemaas_postgres_storage_size` | `10Gi` | PVC size |

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
