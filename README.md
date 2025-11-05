# LiteMaaS Ansible Collection

Deploy LiteMaaS (Models as a Service) on OpenShift in 3 minutes.

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

# 2. Activate k8s virtualenv (required for kubernetes library)
source /opt/virtualenvs/k8s/bin/activate

# 3. Clone the repository
cd ~
git clone https://github.com/prakhar1985/rhpds.litemaas.git
cd rhpds.litemaas

# 4. Install kubernetes.core collection
ansible-galaxy collection install kubernetes.core --force

# 5. Build and install LiteMaaS collection
ansible-galaxy collection build --force
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force

# 6. Deploy with ODF/Ceph storage (common in CNV)
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
echo "LiteLLM Admin Portal: https://$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')"
echo "User API Endpoint: https://$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')"
echo ""
echo "Admin Credentials:"
echo "  Username: $(oc get secret litellm-secret -n rhpds -o jsonpath='{.data.UI_USERNAME}' | base64 -d)"
echo "  Password: $(oc get secret litellm-secret -n rhpds -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)"
echo "========================================="
```

**Quick Commands:**

```bash
# Just get the admin URL
echo "https://$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')"

# Just get the password
oc get secret litellm-secret -n rhpds -o jsonpath='{.data.UI_PASSWORD}' | base64 -d

# Save to file
cat > ~/litemaas-access.txt <<EOF
LiteLLM Admin: https://$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')
Username: $(oc get secret litellm-secret -n rhpds -o jsonpath='{.data.UI_USERNAME}' | base64 -d)
Password: $(oc get secret litellm-secret -n rhpds -o jsonpath='{.data.UI_PASSWORD}' | base64 -d)
EOF
cat ~/litemaas-access.txt
```

## Adding AI Models

Once deployed, add AI models to make them available to users.

### Quick Start: Add OpenShift AI Model (Granite)

1. **Get model details from OpenShift AI dashboard:**
   - Endpoint URL (e.g., `https://granite-3-2-8b-instruct-predictor-maas-apicast-production.apps.maas.redhatworkshops.io:443`)
   - API Key from the OpenShift AI application

2. **Test the endpoint:**
   ```bash
   curl -X POST \
     https://YOUR-GRANITE-ENDPOINT:443/v1/completions \
     -H 'Authorization: Bearer YOUR-API-KEY' \
     -H 'Content-Type: application/json' \
     -d '{
       "model": "granite-3-2-8b-instruct",
       "prompt": "Hello, what is AI?",
       "max_tokens": 50
     }'
   ```

3. **Login to LiteLLM Admin** (use credentials from above)

4. **Add Model → Fill in:**
   ```
   Provider: OpenAI-Compatible Endpoints (Together AI, etc.)
   LiteLLM Model Name(s): openai/granite-3-2-8b-instruct
   Model Mappings:
     Public Name: granite-3-2-8b-instruct
     LiteLLM Model: openai/granite-3-2-8b-instruct
   Mode: Completion - /completions
   API Base: https://YOUR-GRANITE-ENDPOINT:443/v1
   API Key: YOUR-API-KEY
   ```

5. **Click "Add Model"**

### Create Virtual Keys for Users

1. **In LiteLLM Admin → Virtual Keys → Generate Key**
2. **Fill in:**
   ```
   User ID: user@example.com
   Models: openai/granite-3-2-8b-instruct
   Max Budget: 100 (optional)
   Duration: 30d (optional)
   ```
3. **Copy the generated key:** `sk-xxxxxx`
4. **Share with user:**
   ```
   API Endpoint: https://litellm-rhpds.apps.cluster-xxx.opentlc.com
   Virtual Key: sk-xxxxxx
   Model: openai/granite-3-2-8b-instruct
   ```

### Troubleshooting: Virtual Key Model Access

**Issue**: Virtual key returns "key not allowed to access model" error

**Workaround**: Add the model as a default model in Personal Models section:

1. **In LiteLLM Admin UI → Personal Models**
2. **Add the same model** (e.g., `openai/granite-3-2-8b-instruct`)
3. **Set as default model**
4. **Virtual keys should now work**

This is a known workaround - proper fix TBD.

### Test User Access

```bash
# Get LiteLLM URL
LITELLM_URL=$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')

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

All components deploy to the `rhpds` namespace:

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
| `ocp4_workload_litemaas_namespace` | `rhpds` | Deployment namespace |
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

## Status

🚧 **Work in Progress** - Currently testing on AWS

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
